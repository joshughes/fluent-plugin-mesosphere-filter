require 'helper'

class AmplifierFilterTest < Test::Unit::TestCase
  def setup
    unless defined?(Fluent::Filter)
      omit('Fluent::Filter is not defined. Use fluentd 0.12 or later.')
    end

    Fluent::Test.setup
  end

  # config_param :ratio, :float
  # config_param :key_names, :string, :default => nil
  # config_param :key_pattern, :string, :default => nil
  # config_param :floor, :bool, :default => false
  # config_param :remove_prefix, :string, :default => nil
  # config_param :add_prefix, :string, :default => nil

  CONFIG = %[]
  CONFIG2 = %[
    cache_size 2000
    cache_ttl 300
  ]
  CONFIG3 = %[
    get_container_id_tag false
    container_id_attr container_id
  ]

  def create_driver(conf = CONFIG, tag = 'test')
    Fluent::Test::FilterTestDriver.new(Fluent::MesosphereFilter, tag).configure(conf)
  end

  def setup_docker_stub(file, docker_api_url)
    stub_request(:get, docker_api_url)
      .to_return(status: 200, body: file, headers: {})
  end

  def setup_marathon_container(container_id, file_name)
    docker_api_url = "http://tcp//example.com:5422/v1.16/containers/#{container_id}/json"
    file = File.open("test/containers/#{file_name}.json", 'rb')
    setup_docker_stub(file, docker_api_url)
  end

  def setup_chronos_container
    docker_api_url = 'http://tcp//example.com:5422/v1.16/containers/foobar124/json'
    file = File.open('test/containers/chronos.json', 'rb')
    setup_docker_stub(file, docker_api_url)
  end

  def test_marathon_filter
    setup_marathon_container('foobar123', 'marathon')

    d1 = create_driver(CONFIG, 'docker.foobar123')
    d1.run do
      d1.filter('log' => 'Hello World 1')
    end
    filtered = d1.filtered_as_array

    task_id = 'hello-world.14b0596d-93ea-11e5-a134-124eefe69197'

    log_entry = filtered[0][2]

    assert_equal 'marathon', log_entry['mesos_framework']
    assert_equal 'hello-world', log_entry['app']
    assert_equal task_id, log_entry['mesos_task_id']
  end

  def test_container_cache
    setup_marathon_container('foobar123', 'marathon')

    d1 = create_driver(CONFIG, 'docker.foobar123')
    d1.run do
      1000.times do
        d1.filter('log' => 'Hello World 4')
      end
    end
    docker_api_url = 'http://tcp//example.com:5422/v1.16/containers/foobar123/json'

    assert_equal 1000, d1.filtered_as_array.length
    assert_requested(:get, docker_api_url, times: 2)
  end

  def test_container_cache_expiration
    setup_marathon_container('foobar123', 'marathon')

    d1 = create_driver(CONFIG2, 'docker.foobar123')
    d1.run do
      d1.filter('log' => 'Hello World 4')
    end

    Timecop.travel(Time.now + 10 * 60)

    d1.run do
      d1.filter('log' => 'Hello World 4')
    end

    Timecop.return

    docker_api_url = 'http://tcp//example.com:5422/v1.16/containers/foobar123/json'

    assert_requested(:get, docker_api_url, times: 4)
  end

  def test_chronos_filter
    setup_chronos_container

    d1 = create_driver(CONFIG, 'docker.foobar124')
    d1.run do
      d1.filter('log' => 'Hello World 1')
    end
    filtered = d1.filtered_as_array

    task_id = 'ct:1448508194000:0:recurring-transaction2:task'
    log_entry = filtered[0][2]

    assert_equal 'chronos', log_entry['mesos_framework']
    assert_equal 'some-task-app2', log_entry['app']
    assert_equal task_id, log_entry['mesos_task_id']
    assert_equal 'deployTasks', log_entry['chronos_task_type']
  end

  def test_chronos_bad_match
    docker_api_url = 'http://tcp//example.com:5422/v1.16/containers/foobar124/json'
    file = File.open('test/containers/chronos_bad.json', 'rb')
    setup_docker_stub(file, docker_api_url)

    d1 = create_driver(CONFIG, 'docker.foobar124')
    d1.run do
      d1.filter('log' => 'Hello World 1')
    end
    filtered = d1.filtered_as_array

    task_id = 'ct:1448508194000:0:recurring-transaction3:task'
    log_entry = filtered[0][2]

    assert_equal 'chronos', log_entry['mesos_framework']
    assert_equal task_id, log_entry['mesos_task_id']
    refute log_entry['app']
    refute log_entry['chronos_task_type']
  end

  def test_merge_json
    setup_chronos_container

    d1 = create_driver(CONFIG, 'docker.foobar124')
    d1.run do
      d1.filter('log' => '{"test_key":"Hello World"}')
    end
    filtered = d1.filtered_as_array
    log_entry = filtered[0][2]

    assert_equal 'Hello World', log_entry['test_key']
  end

  def test_bad_merge_json
    setup_chronos_container
    bad_json1 = '{"test_key":"Hello World"'
    bad_json2 = '{"test_key":"Hello World", "badnews"}'

    d1 = create_driver(CONFIG, 'docker.foobar124')
    d1.run do
      d1.filter('log' => bad_json1)
      d1.filter('log' => bad_json2)
    end
    filtered = d1.filtered_as_array

    assert_equal bad_json1, filtered[0][2]['log']
    assert_equal bad_json2, filtered[1][2]['log']
  end

  def test_nested_json
    setup_chronos_container
    nested_json = '{"test_key":{"Hello World": "badnews"}}'

    d1 = create_driver(CONFIG, 'docker.foobar124')
    d1.run do
      d1.filter('log' => nested_json)
    end
    filtered = d1.filtered_as_array

    assert_equal '{"Hello World"=>"badnews"}', filtered[0][2]['test_key'].to_s
  end

  def test_container_id_from_record
    setup_marathon_container('somecontainer123', 'marathon2')

    d1 = create_driver(CONFIG3, 'docker')
    d1.run do
      d1.filter('log' => 'hello_world', 'container_id' => 'somecontainer123')
    end
    filtered = d1.filtered_as_array

    task_id = 'hello-world.14b0596d-93ea-11e5-a134-124eefe69197'
    log_entry = filtered[0][2]

    assert_equal 'marathon', log_entry['mesos_framework']
    assert_equal 'hello-world', log_entry['app']
    assert_equal task_id, log_entry['mesos_task_id']
  end
end
