class Capistrano::Alice::Release
  attr_accessor :servers
  attr_accessor :processes
  attr_accessor :path_rules
  attr_accessor :environment
  attr_accessor :deploy_reference
  attr_accessor :repository_reference

  attr_accessor :id
  attr_accessor :number

  def initialize(config)
    @config      = config
    @environment = {}
  end

  def create!
    body = {
      "application"          => @config.application,
      "machines"             => @servers,
      "processes"            => @processes,
      "path_rules"           => (@path_rules || {}).to_a,
      "environment"          => @environment,
      "deploy_reference"     => @deploy_reference,
      "repository_reference" => @repository_reference
    }

    Net::HTTP.start(@config.alice_host, @config.alice_port) do |http|
      request = Net::HTTP::Post.new("/api_v1/releases.json")
      request.body = Yajl::Encoder.encode(body)
      request.content_type = "application/json"
      request['Accepts'] = "application/json"
      response = http.request(request)
      if Net::HTTPSuccess === response
        response = Yajl::Parser.parse(response.body)
        @id          = response['release']['id']
        @number      = response['release']['number']
        @environment = response['release']['environment']
      else
        raise "Failed to create release!"
      end
    end

  end

  def activate!
    Net::HTTP.start(@config.alice_host, @config.alice_port) do |http|
      request = Net::HTTP::Post.new("/api_v1/releases/#{@id}/activate.json")
      request.body = Yajl::Encoder.encode({})
      request.content_type = "application/json"
      request['Accepts'] = "application/json"
      response = http.request(request)
    end
  end

  def destroy!
    Net::HTTP.start(@config.alice_host, @config.alice_port) do |http|
      request = Net::HTTP::Delete.new("/api_v1/releases/#{@id}.json")
      request.content_type = "application/json"
      request['Accepts'] = "application/json"
      response = http.request(request)
    end
  end
end


Capistrano::Configuration.instance(:must_exist).load do
  set(:alice_release) { Capistrano::Alice::Release.new(alice_config) }

  namespace :alice do
    namespace :release do

      # happens before deploy:update_code
      task :create, :except => { :no_release => true } do
        find_and_execute_task("alice:release:_create:collect_servers")
        find_and_execute_task("alice:release:_create:collect_processes")
        find_and_execute_task("alice:release:_create:collect_path_rules")
        find_and_execute_task("alice:release:_create:collect_environment_variables")
        find_and_execute_task("alice:release:_create:detect_ruby_version")
        find_and_execute_task("alice:release:_create:detect_node_version")

        alice_release.deploy_reference     = fetch(:release_name,  nil)
        alice_release.repository_reference = fetch(:real_revision, nil)

        on_rollback { find_and_execute_task("alice:release:destroy") }

        begin
          alice_release.create!
        rescue RuntimeError => e
          abort e.message
        end

        default_environment.merge! alice_release.environment

        if alice_release.environment['RUBY_VERSION']
          set :rvm_ruby_string, alice_release.environment['RUBY_VERSION']
          reset!(:default_shell)
        end

        if alice_release.environment['RAILS_ENV']
          set :rails_env, alice_release.environment['RAILS_ENV']
        end
      end

      task :destroy, :except => { :no_release => true } do
        alice_release.destroy!
      end

      # happens after deploy:restart
      task :activate, :except => { :no_release => true } do
        alice_release.activate!
      end

      namespace :_create do

        task :collect_servers, :except => { :no_release => true } do
          alice_release.servers = find_servers.map(&:to_s)
        end

        task :collect_processes, :except => { :no_release => true } do
          processes = {}

          unless File.file?('Procfile')
            abort "[ALICE]: Missing Procfile!"
          end

          File.read('Procfile').split("\n").each do |line|
            line = line.split('#', 2).first
            name, command = line.split(':', 2)
            name, command = (name || '').strip, (command || '').strip

            next if name.empty? or command.empty?

            processes[name] = command
          end

          if processes.empty?
            abort "[ALICE]: Empty or invalid Procfile!"
          end

          alice_release.processes = processes
        end

        task :collect_path_rules, :except => { :no_release => true } do
          path_rules = {}

          if alice_release.processes.key?('web')
            path_rules.merge!('/*' => [["forward", "web"]])
          end

          if alice_release.processes.key?('static')
            path_rules.merge!(
              '/assets/*' => [
                ["cache-control", "public,max-age=600"],
                ["forward", "static"]
              ],
              '/system/*' => [
                ["cache-control", "public,max-age=600"],
                ["forward", "static"]
              ]
            )

            fetch(:alice_static_paths, []).each do |path|
              path_rules[path] = [
                ["cache-control", "public,max-age=600"],
                ["forward", "static"]
              ]
            end

            Dir.entries('public').each do |path|
              next if path[0,1] == '.'

              if File.directory?(File.join('public',path))
                path_rules[File.join('', path, '*')] = [
                  ["cache-control", "public,max-age=600"],
                  ["forward", "static"]
                ]
              elsif File.file?(File.join('public',path))
                path_rules[File.join('', path)] = [
                  ["cache-control", "public,max-age=600"],
                  ["forward", "static"]
                ]
              end
            end
          end

          path_rules.merge! fetch(:alice_path_rules, {})

          alice_release.path_rules = path_rules
        end

        task :collect_environment_variables, :except => { :no_release => true } do
          env = {}

          if File.file?('.envrc')
            File.read('.envrc').split("\n").each do |line|
              line = line.split('#', 2).first.strip
              case line
              when /^export\s+([a-zA-Z0-9_]+)[=](.+)$/
                env[$1] = $2

              when /^unset\s+([a-zA-Z0-9_]+)$/
                env[$1] = nil

              end
            end
          end

          if rails_env = fetch(:rails_env, nil)
            env['RAILS_ENV'] = rails_env
            env['RACK_ENV']  = rails_env
          end

          if node_env = fetch(:node_env, nil)
            env['NODE_ENV'] = node_env
          end

          env.merge! fetch(:alice_environment, {})

          alice_release.environment.merge! env
        end

        task :detect_ruby_version, :except => { :no_release => true } do
          ruby_version = fetch(:ruby_version, nil)

          if !ruby_version and File.file?('.rvmrc')
            File.read('.rvmrc').split("\n").each do |line|
              line = line.split('#', 2).first.strip
              next unless /^rvm\s+(.+)$/ =~ line
              line = $1
              if /^use\s+(.+)$/ =~ line then line = $1 end
              line = line.split('@', 2).first
              next unless /^[a-z0-9_.-]+$/ =~ line
              ruby_version = line
            end
          end

          alice_release.environment['RUBY_VERSION'] = ruby_version
        end

        task :detect_node_version, :except => { :no_release => true } do
          node_version = fetch(:node_version, nil)

          if !node_version and File.file?('.nvmrc')
            File.read('.nvmrc').split("\n").each do |line|
              line = line.split('#', 2).first.strip
              next unless /^nvm\s+(.+)$/ =~ line
              line = $1
              if /^use\s+(.+)$/ =~ line then line = $1 end
              next unless /^v?([a-z0-9_.-]+)$/ =~ line
              node_version = line
            end
          end

          alice_release.environment['NODE_VERSION'] = node_version
        end

      end
    end
  end
end
