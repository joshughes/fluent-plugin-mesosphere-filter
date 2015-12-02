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
  class MesosphereFilter < Filter
    Fluent::Plugin.register_filter('mesosphere_filter', self)

    config_param :cache_size, :integer, default: 1000
    config_param :cache_ttl, :integer, default: 60 * 60
    config_param :get_container_id_tag, :bool, default: true
    config_param :container_id_attr, :string, default: 'container_id'

    config_param :timestamp_key, :string, default: '@timestamp'
    config_param :merge_json_log, :bool, default: true
    config_param :cronos_task_regex,
                 :string,
                 default: '^(?<app>[a-z0-9]([-a-z0-9.]*[a-z0-9]))-(?<task_type>[^-]+)-(?<run>[^-]+)-(?<epoc>[^-]+)$'

    # Get the configuration for the plugin
    def configure(conf)
      super

      require 'docker-api'
      require 'lru_redux'
      require 'oj'
      require 'time'

      @cache_ttl = :none if @cache_ttl < 0

      @cache = LruRedux::TTL::ThreadSafeCache.new(@cache_size, @cache_ttl)

      @chronos_task_regex_compiled = Regexp.compile(@cronos_task_regex)

      marathon_regex = '\/(?<app>[a-z0-9]([-a-z0-9_.]*[a-z0-9_.]))'
      @marathon_app_regex_compiled = Regexp.compile(marathon_regex)
    end

    # Gets the log event stream and moifies it. This is where the plugin hooks
    # into the fluentd envent stream.
    def filter_stream(tag, es)
      new_es = MultiEventStream.new
      container_id = ''

      container_id = get_container_id_from_tag(tag) if get_container_id_tag

      es.each do |time, record|
        container_id =
          get_container_id_from_record(record) if container_id.empty?
        next unless container_id
        record[@timestamp_key] = generate_time_stamp(time)
        new_es.add(time, modify_record(record, get_mesos_data(container_id)))
      end
      new_es
    end

    # Generates a timestamp that the elasticsearch plugin can understand.
    #
    # ==== Attributes:
    # * +time+ - A time record from the event stream
    # ==== Returns:
    # * A string with the correct datatime format for the elasticsearch plugin
    #   to consume
    def generate_time_stamp(time)
      Time.at(time).utc.strftime('%Y-%m-%dT%H:%M:%S%z')
    end

    # Injects the meso framework data into the record and also merges
    # the json log if that configuration is enabled.
    #
    # ==== Attributes:
    # * +record+ - The log record being processed
    # * +mesos_data+ - The mesos data retrived from the docker container
    #
    # ==== Returns:
    # * A record hash that has mesos data and optinally log data added
    def modify_record(record, mesos_data)
      modified_record = record.merge(mesos_data)
      modified_record = merge_json_log(modified_record) if @merge_json_log
      modified_record
    end

    # Gets the mesos data about a container from the cache or calls the Docker
    # api to retrieve the data about the container and store it in the cache.
    #
    # ==== Attributes:
    # * +container_id+ - The container_id where the log record originated from.
    # ==== Returns:
    # * A hash of data that describes a mesos task
    def get_mesos_data(container_id)
      @cache.getset(container_id) do
        get_container_metadata(container_id)
      end
    end

    # Goes out to docker to get environment variables for a container.
    # Then we parse the environment varibles looking for known Marathon
    # and Chronos environment variables
    #
    # ==== Attributes:
    # * +id+ - The id of the container to look at for mesosphere metadata.
    # ==== Returns:
    # * A hash that describes a mesos task gathered from the Docker API
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
            match_data = parse_env(env).match(@marathon_app_regex_compiled)
            task_data['mesos_framework'] = 'marathon'
            task_data['app'] = match_data['app'] if match_data
          elsif env.include? 'CHRONOS_JOB_NAME'
            match_data = parse_env(env).match(@chronos_task_regex_compiled)
            task_data['mesos_framework'] = 'chronos'
            task_data['app'] = match_data['app'] if match_data
            task_data['chronos_task_type'] = match_data['task_type'] if match_data
          end
        end
      end
      task_data
    end

    # Gets the container id from the last element in the tag. If the user has
    # configured container_id_attr the container id can be gathered from the
    # record if it has been inserted there.
    #
    # ==== Attributes:
    # * +tag+ - The tag of the log being processed
    # ==== Returns:
    # * A docker container id
    def get_container_id_from_tag(tag)
      tag.split('.').last
    end

    # If the user has configured container_id_attr the container id can be
    # gathered from the record if it has been inserted there. If no container_id
    # can be found, the record is not processed.
    #
    # ==== Attributes::
    # * +record+ - The record that is being transformed by the filter
    # ==== Returns:
    # * A docker container id
    def get_container_id_from_record(record)
      record[@container_id_attr]
    end

    # Split the env var on = and return the value
    # ==== Attributes:
    # * +env+ - The docker environment variable to parse to get the value.
    # ==== Examples
    # # For the env value MARATHON_APP_ID the actual string value given to us
    # # by docker is 'MARATHON_APP_ID=some-app'. We want to return 'some-app'.
    # ==== Returns:
    # * The value of an environment varaible
    def parse_env(env)
      env.split('=').last
    end

    # Look at the log value and if it is valid json then we will parse the json
    # and merge it into the log record.
    # ==== Attributes:
    # * +record+ - The record we are transforming in the fluentd event stream.
    # ==== Examples
    # # Docker captures stdout and passes it in the 'log' record attribute.
    # # We try to discover is the value of 'log' is json, if it is then we
    # # will parse the json and add the keys and values to the record.
    # ==== Returns:
    # * A record hash that has json log data merged into the record
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
