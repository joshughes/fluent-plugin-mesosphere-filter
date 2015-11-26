#
# Fluentd Mesosphere Metadata Filter Plugin
#
# Copyright 2015 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
module Fluent
  # Parses Marathon and Chronos data from docker to make fluentd logs more
  # useful.
  class MesosphereFilter < Fluent::Filter
    Fluent::Plugin.register_filter('mesosphere-filter', self)

    config_param :cache_size, :integer, default: 1000
    config_param :cache_ttl, :integer, default: 60 * 60

    config_param :merge_json_log, :bool, default: true
    config_param :cronos_task_regex,
                 :string,
                 default: '(?<app>[a-z0-9]([-a-z0-9]*[a-z0-9]))-(?<date>[^-]+)-(?<time>[^-]+)-(?<task_type>[^-]+)-(?<run>[^-]+)-(?<epoc>[^-]+)'

    def initialize
      super
    end

    # Get the configuration for the plugin
    def configure(conf)
      super

      require 'docker-api'
      require 'lru_redux'
      require 'oj'

      @cache_ttl = :none if @cache_ttl < 0

      @cache = LruRedux::TTL::ThreadSafeCache.new(@cache_size, @cache_ttl)

      @chronos_task_regex_compiled = Regexp.compile(@cronos_task_regex)
    end

    # Gets the log event stream and moifies it. This is where the plugin hooks
    # into the fluentd envent stream.
    def filter_stream(tag, es)
      new_es = MultiEventStream.new

      container_id = tag.split('.').last
      mesos_data = @cache.getset(container_id) do
        get_container_metadata(container_id)
      end

      es.each do |time, record|
        record = record.merge(mesos_data)
        record = merge_json_log(record) if @merge_json_log
        new_es.add(time, record)
      end

      new_es
    end

    # Goes out to docker to get environment variables for a container.
    # Then we parse the environment varibles looking for known Marathon
    # and Chronos environment variables
    #
    # ==== Attributes
    # * +id+ - The id of the container to look at for mesosphere metadata.
    def get_container_metadata(id)
      task_data = {}
      container = Docker::Container.get(id)
      if container
        environment = container.json['Config']['Env']
        environment.each do |env|
          # Chronos puts task_id in lowercase, and Marathon does it with
          # uppercase
          if env =~ /MESOS_TASK_ID/i
            task_data['mesos_task_id'] = parse_env(env)
          elsif env.include? 'MARATHON_APP_ID'
            task_data['mesos_framework'] = 'marathon'
            task_data['app'] = parse_env(env)
          elsif env.include? 'CHRONOS_JOB_NAME'
            match_data = parse_env(env).match(@chronos_task_regex_compiled)
            task_data['mesos_framework'] = 'chronos'
            task_data['app'] = match_data['app']
            task_data['chronos_task_type'] = match_data['task_type']
          end
        end
      end
      task_data
    end

    # Split the env var on = and return the value
    # ==== Attributes
    # * +env+ - The docker environment variable to parse to get the value.
    # ==== Examples
    # # For the env value MARATHON_APP_ID the actual string value given to us
    # # by docker is 'MARATHON_APP_ID=some-app'. We want to return 'some-app'.
    def parse_env(env)
      env.split('=').last
    end

    # Look at the log value and if it is valid json then we will parse the json
    # and merge it into the log record.
    # ==== Attributes
    # * +record+ - The record we are transforming in the fluentd event stream.
    # ==== Examples
    # # Docker captures stdout and passes it in the 'log' record attribute.
    # # We try to discover is the value of 'log' is json, if it is then we
    # # will parse the json and add the keys and values to the record.
    def merge_json_log(record)
      if record.key?('log')
        log = record['log'].strip
        if log[0].eql?('{') && log[-1].eql?('}')
          begin
            record = Oj.load(log).merge(record)
          rescue Oj::ParseError
          end
        end
      end
      record
    end
  end
end
