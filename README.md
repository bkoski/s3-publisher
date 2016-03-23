# s3-publisher

Quickly pub your data files to S3.

**This version depends on aws-sdk 2.x.  For aws-sdk 1.x projects, use version <= 1.0 of this gem.**

Reasons you might want to use this instead of aws-sdk directly:

  * parallel uploads using ruby threads.  Concurrency defaults to 3 but can be increased.
  * gzip, by default S3Publisher gzips so you don't have to.
  * try-again technology, it will retry if a S3 request fails.
  * no need to remember all the correct opts for content-type, acl, etc.

### Basic usage:

```
require 's3-publisher'
S3Publisher.publish('my-bucket') do |p|
   p.push('test.txt', data: 'abc1234')
end
```

This will:

 * push test.txt to my-bucket.s3.amazonaws.com
 * set security to public-read
 * gzip contents ('abc1234') and set a Content-Encoding: gzip header so clients know to decompress
 * set a Cache-Control: max-age=5 header


You can also pass file paths, rather than string data.  Files aren't read until publish time, saving memory.

```
require 's3-publisher'
S3Publisher.publish('my-bucket') do |p|
   p.push('test.json', file: '/tmp/test.json')
end
```

### Slightly more advanced example:

```
S3Publisher.publish('my-bucket', base_path: 'world_cup', region: 'us-west-1') do |p|
    p.push('events.xml', data: '<xml>...', ttl: 15)
end
```

In this example:

 * file will be written to my-bucket.s3.amazonaws.com/world_cup/events.xml
 * Cache-Control: max-age=15 will be set
 * files will be published into the us-west-1 AWS region (If not specified, this takes the AWS client default.  Normally this is not necessary unless you are publishing to two regions from the same session.)

See class docs for more options.

### AWS Credentials

Since S3Publisher uses [aws-sdk](https://github.com/aws/aws-sdk-ruby) any of the usual credential stores will work, including:

 * `ENV['AWS_ACCESS_KEY_ID'], ENV['AWS_SECRET_ACCESS_KEY'], ENV['AWS_REGION']`
 * IAM role
 * ```
  Aws.config.update({
    region: 'us-west-2',
    credentials: Aws::Credentials.new('akid', 'secret')
  })
  ```