require 'spec_helper'

describe S3Publisher do  
  describe "#push" do
           
    describe "file_name" do
      it "prepends base_path if provided", focus: true do
        set_put_expectation(key_name: 'world_cup_2010/events.xml')
        p = S3Publisher.new('test-bucket', logger: Logger.new(nil), base_path: 'world_cup_2010')
        p.push('events.xml', data: '1234')
        p.run
      end
      
      it "passes name through unaltered if base_path not specified" do
        set_put_expectation(key_name: 'events.xml')
        p = S3Publisher.new('test-bucket', logger: Logger.new(nil))
        p.push('events.xml', data: '1234')
        p.run
      end      
    end
    
    describe "gzip" do
      it "gzips data if :gzip => true" do
        set_put_expectation(data: gzip('1234'))
        push_test_data('myfile.txt', data: '1234', gzip: true)
      end
      
      it "does not gzip data if :gzip => false" do
        set_put_expectation(data: '1234')
        push_test_data('myfile.txt', data: '1234', gzip: false)
      end

      it "does not gzip image files" do
        set_put_expectation(key_name: 'myfile.jpg', data: '1234')
        push_test_data('myfile.jpg', data: '1234')
      end
      
      it "gzips data by default" do
        set_put_expectation(data: gzip('1234'))
        push_test_data('myfile.txt', data: '1234')
      end
    end

    describe ":file opt" do
      it "queues contents of files if gzip is false" do
        set_put_expectation(file: __FILE__)
        push_test_data('myfile.txt', file: __FILE__, gzip: false)
      end

      it "queues gzipped contents of the file if gzip is true" do
        set_put_expectation(data: gzip(File.read(__FILE__)))
        push_test_data('myfile.txt', file: __FILE__, gzip: true)
      end
    end
    
    describe "content type" do
      it "detects content type based on extension" do
        set_put_expectation(key_name: 'myfile.xml', content_type: 'application/xml')
        push_test_data('myfile.xml', data: '1234')
      end
      
      it "forces Content-Type to user-supplied string if provided" do
        set_put_expectation(content_type: 'audio/vorbis')
        push_test_data('myfile.txt', data: '1234', content_type: 'audio/vorbis')
      end

      it "raises an exception if the content-type cannot be parsed" do
        expect { push_test_data('myfile', data: '1234') }.to raise_error(ArgumentError)
      end
    end

    describe "cache-control" do
      it "sets Cache-Control to user-supplied string if :cache_control provided" do
        set_put_expectation(cache_control: 'private, max-age=0')
        push_test_data('myfile.txt', data: '1234', cache_control: 'private, max-age=0')
      end
      
      it "sets Cache-Control with :ttl provided" do
        set_put_expectation(cache_control: 'max-age=55')
        push_test_data('myfile.txt', data: '1234', ttl: 55)
      end
      
      it "sets Cache-Control to a 5s ttl if no :ttl or :cache_control was provided" do
        set_put_expectation(cache_control: 'max-age=5')
        push_test_data('myfile.txt', data: '1234')
      end
    end

    describe "acl" do
      it "sets ACL to user-supplied string if :acl provided" do
        set_put_expectation(acl: 'private')
        push_test_data('myfile.txt', data: '1234', acl: 'private')
      end

      it "sets ACL to public-read when no option is provded" do
        set_put_expectation(acl: 'public-read')
        push_test_data('myfile.txt', data: '1234')
      end
    end
    
    # Based on opts, sets expecations for AWS::S3Object.write
    # Can provide expected values for:
    #  * :key_name
    #  * :data
    #  * :content_type, :cache_control, :content_encoding, :acl
    def set_put_expectation opts
      key_name = opts[:key_name] || 'myfile.txt'

      expected_entries = {}
      [:content_type, :cache_control, :content_encoding, :acl].each do |k|
        expected_entries[k] = opts[k] if opts.has_key?(k)
      end

      if opts[:data]
        expected_contents = opts[:data]
      elsif opts[:file]
        expected_contents = Pathname.new(opts[:file]).read
      else
        expected_contents = anything
      end

      expected_entries.merge!(bucket: 'test-bucket', key: key_name, body: expected_contents)

      Aws::S3::Client.any_instance.expects(:put_object).with(has_entries(expected_entries))
    end
    
    def gzip data
      gzipped_data = StringIO.open('', 'w+')
      
      gzip_writer = Zlib::GzipWriter.new(gzipped_data)
      gzip_writer.write(data)
      gzip_writer.close
      
      return gzipped_data.string
    end
    
    def push_test_data file_name, opts
      p = S3Publisher.new('test-bucket', logger: Logger.new(nil))
      p.push(file_name, opts)
      p.run
    end
  end  
end
