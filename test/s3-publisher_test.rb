require 'test_helper'

class S3PublisherTest < Test::Unit::TestCase
  
  context "push" do
           
    context "file_name" do
      should "prepend base_path if provided on instantiate" do
        set_put_expectation(:key_name => 'world_cup_2010/events.xml')
        p = S3Publisher.new('test-bucket', :logger => Logger.new(nil), :base_path => 'world_cup_2010')
        p.push('events.xml', '1234')
        p.run
      end
      
      should "pass through unaltered if base_path not specified" do
        set_put_expectation(:key_name => 'events.xml')
        p = S3Publisher.new('test-bucket', :logger => Logger.new(nil))
        p.push('events.xml', '1234')
        p.run
      end      
    end
    
    context "gzip" do
      should "gzip data if :gzip => true" do
        set_put_expectation(:data => gzip('1234'))
        push_test_data('myfile.txt', '1234', :gzip => true)
      end
      
      should "not gzip data if :gzip => false" do
        set_put_expectation(:data => '1234')
        push_test_data('myfile.txt', '1234', :gzip => false)
      end

      should "not gzip data if file ends in .jpg" do
        set_put_expectation(:data => '1234')
        push_test_data('myfile.jpg', '1234', {})
      end
      
      should "gzip data by default" do
        set_put_expectation(:data => gzip('1234'))
        push_test_data('myfile.txt', '1234', {})
      end
    end
    
    context "redundancy" do
      should "set REDUCED_REDUNDANCY by default" do
        set_put_expectation(:headers => { 'x-amz-storage-class' => 'REDUCED_REDUNDANCY' })
        push_test_data('myfile.txt', '1234', {})

      end
      
      should "set STANDARD if :redundancy => :standard is passed" do
        set_put_expectation(:headers => { 'x-amz-storage-class' => 'STANDARD' })
        push_test_data('myfile.txt', '1234', :redundancy => :standard)
      end
    end

    context "content type" do
      should "force Content-Type to user-supplied string if provided" do
        set_put_expectation(:headers => { 'Content-Type' => 'audio/vorbis' })
        push_test_data('myfile.txt', '1234', :content_type => 'audio/vorbis')
      end
      
      should "force Content-Type to application/xml if :xml provided" do
        set_put_expectation(:headers => { 'Content-Type' => 'application/xml' })
        push_test_data('myfile.txt', '1234', :content_type => :xml)
      end
      
      should "force Content-Type to text/plain if :text provided" do
        set_put_expectation(:headers => { 'Content-Type' => 'text/plain' })
        push_test_data('myfile.txt', '1234', :content_type => :text)
      end
      
      should "force Content-Type to text/html if :html provided" do
        set_put_expectation(:headers => { 'Content-Type' => 'text/html' })
        push_test_data('myfile.txt', '1234', :content_type => :html)
      end
    end

    context "cache-control" do
      should "set Cache-Control to user-supplied string if :cache_control provided" do
        set_put_expectation(:headers => { 'Cache-Control' => 'private, max-age=0' })
        push_test_data('myfile.txt', '1234', :cache_control => 'private, max-age=0')
      end
      
      should "set Cache-Control with :ttl provided" do
        set_put_expectation(:headers => { 'Cache-Control' => 'max-age=55' })
        push_test_data('myfile.txt', '1234', :ttl => 55)
      end
      
      should "set Cache-Control to a 5s ttl if no :ttl or :cache_control was provided" do
        set_put_expectation(:headers => { 'Cache-Control' => 'max-age=5' })
        push_test_data('myfile.txt', '1234', {})
      end
    end
    
    
    
    
  end
  
  def set_put_expectation opts
    s3_stub = mock()
    bucket_stub = mock()
    bucket_stub.expects(:put).with(opts[:key_name] || anything, opts[:data] || anything, {}, 'public-read', opts[:headers] ? has_entries(opts[:headers]) : anything)
    
    s3_stub.stubs(:bucket).returns(bucket_stub)
    RightAws::S3.stubs(:new).returns(s3_stub)
  end
  
  def gzip data
    gzipped_data = StringIO.open('', 'w+')
    
    gzip_writer = Zlib::GzipWriter.new(gzipped_data)
    gzip_writer.write(data)
    gzip_writer.close
    
    return gzipped_data.string
  end
  
  def push_test_data file_name, data, opts
    p = S3Publisher.new('test-bucket', :logger => Logger.new(nil))
    p.push(file_name, data, opts)
    p.run
  end
  
end
