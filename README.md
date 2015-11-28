#Mesosphere Fluentd Filter
[![Code Climate](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter/badges/gpa.svg)](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter)
[![Test Coverage](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter/badges/coverage.svg)](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter/coverage)
[![Gem Version](https://badge.fury.io/rb/fluent-plugin-mesosphere-filter.svg)](https://badge.fury.io/rb/fluent-plugin-mesosphere-filter)
[![Inline docs](http://inch-ci.org/github/joshughes/fluent-plugin-mesosphere-filter.svg?branch=master)](http://inch-ci.org/github/joshughes/fluent-plugin-mesosphere-filter)
[![Dependency Status](https://www.versioneye.com/user/projects/5658d10aaef3b5003e000000/badge.svg?style=flat)](https://www.versioneye.com/user/projects/5658d10aaef3b5003e000000)

Marathon, Chronos and Mesos combined can allow for teams to build a great solution for deploying and scaling containers. The issue is when you have a system like Kibana it can be hard to identify what container or task a log is coming from.

This filter aims to solve that issue by inspecting containers to inject Mesosphere metatdata into the Fluentd event stream.

##What gets injected?
###Marathon

|`key`|  Description  |
|---|---|
|`app`|  The application name in marathon  |
|  `mesos_framework` |  marathon |
| `mesos_task_id` | The unique Mesos task id running the docker container |

###Chronos
Chronos does not have the idea of an 'application'. Just jobs. We run a lot of jobs that relate to our applications so we use a naming scheme that allows us to extract the marathon application that is running the Chronos task.

An example of a Chronos Job name is the following.

`some-task-app2-11182015-1718-deployTasks-1-144786721`

With the default regex in the plugin we extract the following data and inject it into the event stream.

|`key`|  Description  | Value |
|---|---|---|
|`app`|  The application name running the task  | some-task-app2 |
|  `mesos_framework` |  chronos | chronos |
| `mesos_task_id` | The unique Mesos task id running the docker container | |
| `chronos_task_type` | The task type our application is running. We run deployment and scheduled tasks. | deployTasks |

##Configuration

If your using the docker fluentd logging plugin your configuration should look something like this.

```
<source>
  type forward
  port 24224
  bind 0.0.0.0
</source>

<filter docker.*>
  type mesosphere-filter
  cache_size 1000
  cache_ttl 3600
  merge_json_log true
  cronos_task_regex (?<app>[a-z0-9]([-a-z0-9]*[a-z0-9]))-(?<date>[^-]+)-(?<time>[^-]+)-(?<task_type>[^-]+)-(?<run>[^-]+)-(?<epoc>[^-]+)
</filter>

<match docker.*>
  type stdout
</match>
```

|`key`|  Description  | Default |
|---|---|---|
|`cache_size`|  This plugin will cache information from the docker daemon. This configuration determine how large that cache is. | 1000 |
|  `cache_ttl ` |  How long to keep items in the cache. | 3600 |
| `merge_json_log ` | If your application logs in a valid json format, this will merge that into the event stream. | true |
| `cronos_task_regex ` | If you don't provide a valid regex here then you will only get the mesos_task id from until you create a standard chronos job name that is parseable by a ruby regex. | **See example above** |


##Example
We have an application called `hello-world`. That application is deployed via marathon and has the following environment variables.

|`key`|  value  |
|---|---|
| `MESOS_TASK_ID` | `hello-world.14b0596d-93ea-11e5-a134-124eefe69197`|
| `MARATHON_APP_ID` | `/hello-world`|

Like all great hello world applications. This docker container just execute:

```bash
echo '{"say":"Hello World"}'
```

Without this filter fluentd would process the docker log and output the following.

```json
{
	"container_id": "ce327cb0de115f7dbfcd2c6055ba945436dada26035a62587b951332a028a530",
	"container_name": "/some_random_meaningless_name",
	"source": "stdout",
	"log": "{\"say\":\"Hello World\"}\r"
}
```

With the filter in place that log will become the following.

```json
{
	"container_id": "ce327cb0de115f7dbfcd2c6055ba945436dada26035a62587b951332a028a530",
	"container_name": "/some_random_meaningless_name",
	"say": "Hello World",
	"mesos_framework": "marathon",
	"app": "hello-world",
	"mesos_task_id": "unquie_task_id",
	"source": "stdout",
	"log": "{\"say\":\"Hello World\"}\r"
}
```

So now in Kibana you can filter on many more fields and more easily track down issues when `hello-world` may be running in multiple containers that are associated with different Mesos tasks.
