require 'zlib'
require 'thread'
require 'pathname'

require 'aws-sdk'
require 'mime-types'

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

  # @param [String] bucket_name
  # @option opts [String] :base_path Path prepended to supplied file_name on upload
  # @option opts [Integer] :workers Number of threads to use when pushing to S3. Defaults to 3.
  # @option opts [Object] :logger A logger object to recieve 'uploaded' messages.  Defaults to STDOUT.
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

  # Queues a file to be published.
  # You can provide :data as a string, or a path to a file with :file.
  # :file references won't be evaluated until publish-time, reducing memory overhead.
  #
  # @param [String] key_name  The name of the file on S3.  base_path will be prepended if supplied.
  # @option opts [String] :data  a string to be published
  # @option opts [String] :file  path to a file to publish
  # @option opts [Boolean] :gzip  gzip file contents?  defaults to true.
  # @option opts [Integer] :ttl  TTL in seconds for cache-control header. defaults to 5.
  # @option opts [String] :cache_control  specify Cache-Control header directly if you don't like the default
  # @option opts [String] :content_type  no need to specify if default based on extension is okay.  But if you need to force,
  #                                      you can provide :xml, :html, :text, or your own custom string.
  def push key_name, opts={}
    write_opts = { acl: 'public-read' }
    
    key_name = "#{base_path}/#{key_name}" unless base_path.nil?
    
    # Setup data.
    if opts[:data]
      contents = opts[:data]
    elsif opts[:file]
      contents = Pathname.new(opts[:file])
      raise ArgumentError, "'#{opts[:file]}' does not exist!" if !contents.exist?
    else
      raise ArgumentError, "A :file or :data attr must be provided to publish to S3!"
    end

    # Then Content-Type
    if opts[:content_type]
      write_opts[:content_type] = opts[:content_type]
    else
      matching_mimes = MIME::Types.type_for(key_name)
      raise  ArgumentError, "Can't infer the content-type for '#{key_name}'! Please specify with the :content_type opt." if matching_mimes.empty?
      write_opts[:content_type] = matching_mimes.first.to_s
    end

    # And Cache-Control
    if opts.has_key?(:cache_control)
      write_opts[:cache_control] = opts[:cache_control]
    else
      write_opts[:cache_control] = "max-age=#{opts[:ttl] || 5}"
    end

    opts[:gzip] = true unless opts.has_key?(:gzip)

    @publish_queue.push({ key_name: key_name, contents: contents, write_opts: write_opts, gzip: opts[:gzip] })
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
  
  def publish_from_queue
    loop do
      item = @publish_queue.pop(true)
    
      try_count = 0
      begin
        obj = @s3.buckets[bucket_name].objects[item[:key_name]]

        gzip = item[:gzip] != false && !item[:key_name].match(/\.(jpg|gif|png|tif)$/)

        if gzip
          item[:write_opts][:content_encoding] = 'gzip'
          gzip_body = item[:contents].is_a?(Pathname) ? item[:contents].read : item[:contents]
          item[:contents] = gzip(gzip_body)
        end

        obj.write(item[:contents], item[:write_opts])

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