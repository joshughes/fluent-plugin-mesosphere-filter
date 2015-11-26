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

    def configure(conf)
      super

      require 'docker-api'
      require 'lru_redux'
      require 'oj'

      @cache_ttl = :none if @cache_ttl < 0

      @cache = LruRedux::TTL::ThreadSafeCache.new(@cache_size, @cache_ttl)

      @chronos_task_regex_compiled = Regexp.compile(@cronos_task_regex)
    end

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

    def get_container_metadata(id)
      task_data = {}
      container = Docker::Container.get(id)
      if container
        environment = container.json['Config']['Env']
        environment.each do |env|
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

    def parse_env(env)
      env.split('=').last
    end

    def merge_json_log(record)
      if record.has_key?('log')
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
