require "simplecov"
SimpleCov.start

require 'rubygems'
require 'bundler'
require 'docker'
require 'timecop'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'test/unit'
require 'pry'


require "simplecov"
require "codeclimate-test-reporter"
if ENV['CIRCLE_ARTIFACTS']
  dir = File.join("..", "..", "..", ENV['CIRCLE_ARTIFACTS'], "coverage")
  SimpleCov.coverage_dir(dir)
end



$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'fluent/test'
require 'fluent/test/driver/filter'
require 'webmock/test_unit'
WebMock.disable_net_connect!(:allow => "codeclimate.com")

if ENV.has_key?('VERBOSE')
  $log = Fluent::Log.new(Fluent::Test::DummyLogDevice.new, Fluent::Log::LEVEL_TRACE)
else
  nulllogger = Object.new
  nulllogger.instance_eval {|obj|
    def method_missing(method, *args)
      # pass
    end
  }
  $log = nulllogger
end
Docker.url = 'tcp://example.com:5422'
require 'fluent/plugin/filter_mesosphere_filter'

class Test::Unit::TestCase
end
