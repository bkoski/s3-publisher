require 'zlib'
require 'thread'

require 'aws-sdk'
require 'aws_credentials'

# You can either use the block syntax, or:
# * instantiate a class
# * queue data to be published with push
# * call run to actually upload the data to S3
class S3Publisher
  
  attr_reader :bucket_name, :base_path, :logger, :workers_to_use

  # Block style.  run is called for you on block close.
  #  S3Publisher.publish('my-bucket') do |p|
  #    p.push('test.txt', '123abc')
  #  end
  def self.publish bucket_name, opts={}, &block
    p = self.new(bucket_name, opts)
    yield(p)
    p.run
  end

  # Pass the publisher a bucket_name along with any of the following options:
  # * <tt>base_path</tt> - path prepended to supplied file_name on upload
  # * <tt>logger</tt> - a logger object to recieve 'uploaded' messages.  Defaults to STDOUT.
  # * <tt>workers</tt> - number of threads to use when pushing to S3. Defaults to 3.
  def initialize bucket_name, opts={}
    @publish_queue = Queue.new
    @workers_to_use = opts[:workers] || 3
    @logger = opts[:logger] || $stdout

    s3_opts = {}
    s3_opts[:access_key_id]     = opts[:access_key_id]     if opts.key?(:access_key_id)
    s3_opts[:secret_access_key] = opts[:secret_access_key] if opts.key?(:secret_access_key)
    
    @s3 = AWS::S3.new(s3_opts)

    @bucket_name, @base_path = bucket_name, opts[:base_path]
    raise ArgumentError, "#{bucket_name} doesn't seem to be a valid bucket on your account" if @s3.buckets[bucket_name].nil?
  end
  
  # Pass:
  # * <tt>file_name</tt> - name of file on S3. base_path will be prepended if supplied on instantiate.
  # * <tt>data</tt> - data to be uploaded as a string
  #
  # And one or many options:
  # * <tt>:gzip (true|false)</tt> - gzip file contents?  defaults to true.
  # * <tt>:ttl</tt> - TTL in seconds for cache-control header. defaults to 5.
  # * <tt>:cache_control</tt> - specify Cache-Control header directly if you don't like the default
  # * <tt>:content_type</tt> - no need to specify if default based on extension is okay.  But if you need to force,
  #   you can provide :xml, :html, :text, or your own custom string.
  # * <tt>:redundancy</tt> - by default objects are stored at reduced redundancy, pass :standard to store at full
  def push file_name, data, opts={}
    write_opts = {}
    
    file_name = "#{base_path}/#{file_name}" unless base_path.nil?
    
    unless opts[:gzip] == false || file_name.match(/\.(jpg|gif|png|tif)$/)
      data = gzip(data)
      write_opts[:content_encoding] = 'gzip'
    end
    
    write_opts[:content_type] = parse_content_type(opts[:content_type])  if opts[:content_type]

    if opts.has_key?(:cache_control)
      write_opts[:cache_control] = opts[:cache_control]
    else
      write_opts[:cache_control] = "max-age=#{opts[:ttl] || 5}"
    end

    @publish_queue.push({ key_name: file_name, data: data, write_opts: write_opts })
  end  
    
  # Process queued uploads and push to S3
  def run
    threads = []
    workers_to_use.times { threads << Thread.new { publish_from_queue } }
    threads.each { |t| t.join }
    true
  end
  
  def inspect
    "#<S3Publisher:#{bucket_name}>"
  end
  
  private
  def gzip data
    gzipped_data = StringIO.open('', 'w+')
    
    gzip_writer = Zlib::GzipWriter.new(gzipped_data)
    gzip_writer.write(data)
    gzip_writer.close
    
    return gzipped_data.string
  end
    
  def parse_content_type content_type
    case content_type
    when :xml
      'application/xml'
    when :text
      'text/plain'
    when :html
      'text/html'
    else
      content_type
    end
  end
  
  def publish_from_queue
    loop do
      item = @publish_queue.pop(true)
    
      try_count = 0
      begin
        obj = @s3.buckets[bucket_name].objects[item[:key_name]]
        obj.write(item[:data], item[:write_opts].merge(acl: 'public-read'))
      rescue Exception => e # backstop against transient S3 errors
        raise e if try_count >= 1
        try_count += 1
        retry
      end
    
      logger << "Wrote http://#{bucket_name}.s3.amazonaws.com/#{item[:key_name]} with #{item[:write_opts].inspect}\n"
    end
  rescue ThreadError  # ThreadError hit when queue is empty.  Simply jump out of loop and return to join().
  end
  
end