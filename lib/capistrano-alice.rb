require 'net/http'
require 'yajl'

module Capistrano
  module Alice
    require "capistrano-alice/version"
  end
end

class Capistrano::Alice::Configuration

  attr_accessor :alice_host
  attr_accessor :alice_port
  attr_accessor :application

end

Capistrano::Configuration.instance(:must_exist).load do
  require 'capistrano-alice/maintenance_mode'
  require 'capistrano-alice/release_managment'

  set :alice_application do
    application
  end

  set :alice_config do
    conf = Capistrano::Alice::Configuration.new
    conf.alice_host  = alice_host
    conf.alice_port  = alice_port
    conf.application = alice_application
    conf
  end

  before "deploy:update_code", "alice:maintenance:on"
  before "deploy:update_code", "alice:release:create"
  after  "deploy:update_code", "alice:release:procfile"
  after  "deploy:restart",     "alice:release:activate"
  after  "deploy:restart",     "alice:maintenance:off"
end
