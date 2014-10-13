# coding: utf-8

Gem::Specification.new do |s|
  s.name        = "s3-publisher"
  s.version     = "0.9.2"
  s.authors     = ["Ben Koski"]
  s.email       = "bkoski@nytimes.com"
  s.summary     = "Publish data to S3 for the world to see"
  s.description = "Publish data to S3 for the world to see"
  s.homepage    = "http://github.com/bkoski/s3-publisher"
  s.license     = 'MIT'

  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})

  s.require_paths = ["lib"]

  s.add_development_dependency(%q<rspec>, [">= 0"])
  s.add_runtime_dependency(%q<aws-sdk>, [">= 1.0"])
  s.add_runtime_dependency(%q<mime-types>, [">= 0"])
end