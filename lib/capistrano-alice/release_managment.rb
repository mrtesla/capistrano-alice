class Capistrano::Alice::Release
  attr_accessor :servers
  attr_accessor :processes
  attr_accessor :path_rules

  attr_accessor :id
  attr_accessor :number

  def initialize(config)
    @config = config
  end

  def create!
    body = {
      "application" => @config.application,
      "machines"    => @servers,
      "processes"   => @processes,
      "path_rules"  => (@path_rules || {}).to_a
    }

    Net::HTTP.start(@config.alice_host, @config.alice_port) do |http|
      request = Net::HTTP::Post.new("/api_v1/releases.json")
      request.body = Yajl::Encoder.encode(body)
      request.content_type = "application/json"
      request['Accepts'] = "application/json"
      response = http.request(request)
      if Net::HTTPSuccess === response
        response = Yajl::Parser.parse(response.body)
        @id     = response['release']['id']
        @number = response['release']['number']
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

        on_rollback { find_and_execute_task("alice:release:destroy") }

        alice_release.create!
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

              if File.directory?(path)
                path_rules[File.join('', path, '*')] = [
                  ["cache-control", "public,max-age=600"],
                  ["forward", "static"]
                ]
              elsif File.file?(path)
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

      end
    end
  end
end
