# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |gem|
  gem.name          = 'fluent-plugin-mesosphere-filter'
  gem.version       = '0.1.6'
  gem.authors       = ['Joseph Hughes']
  gem.email         = ['jjhughes57@gmail.com']
  gem.description   = 'Filter plugin to add Mesosphere metadata'
  gem.summary       = 'Filter plugin to add Mesosphere metadata to fluentd from Chronos and Marathon'
  gem.homepage      = 'https://github.com/joshughes/fluent-plugin-mesosphere-filter'
  gem.license       = 'ASL2'

  gem.files         = `git ls-files`.split($RS)
  gem.executables   = gem.files.grep(%r{^bin/}) { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  gem.has_rdoc      = false

  gem.required_ruby_version = '>= 2.0.0'

  gem.add_runtime_dependency 'fluentd', '>= 0.10.43'
  gem.add_runtime_dependency 'lru_redux', '~> 1.1'
  gem.add_runtime_dependency 'docker-api', '~> 1.23'
  gem.add_runtime_dependency 'oj', '>= 2.13.1'

  gem.add_development_dependency 'bundler', '~> 1.3'
  gem.add_development_dependency 'codeclimate-test-reporter'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'webmock'
  gem.add_development_dependency 'pry'
  gem.add_development_dependency 'timecop'
  gem.add_development_dependency 'simplecov'
  gem.add_development_dependency 'minitest', '~> 4.0'
end
