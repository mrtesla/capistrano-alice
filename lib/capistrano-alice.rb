require "capistrano-alice/version"

module Capistrano
  module Alice
    # Your code goes here...
  end
end

Capistrano::Configuration.instance(:must_exist).load do
  # previous file contents here
end
