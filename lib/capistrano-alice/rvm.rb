begin
  require "rvm/capistrano"
rescue LoadError
  require "capistrano-alice/rvm_capistrano"
end
