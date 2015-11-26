#Mesospher Fluentd Filter
[![Code Climate](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter/badges/gpa.svg)](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter)
[![Test Coverage](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter/badges/coverage.svg)](https://codeclimate.com/github/joshughes/fluent-plugin-mesosphere-filter/coverage)
[![Gem Version](https://badge.fury.io/rb/fluent-plugin-mesosphere-filter.svg)](https://badge.fury.io/rb/fluent-plugin-mesosphere-filter)
[![Inline docs](http://inch-ci.org/github/joshughes/fluent-plugin-mesosphere-filter.svg?branch=master)](http://inch-ci.org/github/joshughes/fluent-plugin-mesosphere-filter)

Marathon, Chronos and Mesos combined can allow for teams to build a great solution for deploying and scaling containers. The issue is when you have a system like Kibana it can be hard to identify what container or task a log is coming from. 

This filter aims to solve that issue by adding 