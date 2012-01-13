class Capistrano::Alice::Release
  attr_accessor :servers
  attr_accessor :processes
  attr_accessor :path_rules

  def create!
    body = {
      "machines"   : @servers
      "processes"  : @processes
      "path_rules" : (@path_rules || {}).to_a
    }

    body = Yajl::Encoder.encode(body)
  end
end


Capistrano::Configuration.instance(:must_exist).load do
  set(:release) { Capistrano::Alice::Release.new }

  # happens before deploy:update_code
  task "alice:release:create", :except => { :no_release => true } do
    find_and_execute_task("alice:release:create:collect_servers")
    find_and_execute_task("alice:release:create:collect_processes")
    find_and_execute_task("alice:release:create:path_rules")

    on_rollback { find_and_execute_task("alice:release:destroy") }


  end

  task "alice:release:destroy", :except => { :no_release => true } do

  end

  # happens after deploy:restart
  task "alice:release:activate", :except => { :no_release => true } do

  end

  namespace "alice::release:create" do

    task "collect_servers": :except => { :no_release => true } do
      release.servers = find_servers
    end

    task "collect_processes", :except => { :no_release => true } do
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

      release.processes = processes
    end

    task "collect_path_rules", :except => { :no_release => true } do
      path_rules = {}

      if release.processes.key?('web')
        path_rules.merge!('/*' => [["forward", "web"]])
      end

      if release.processes.key?('static')
        Dir.glob('public/*').each do |path|
          next if path[0,1] == '.'

          if File.directory?(path)
            pattern = '/' + File.basename(path) + '/*'
            path_rules[pattern] = [
              ["cache-control", "public,max-age=600"],
              ["forward", "static"]
            ]
          elsif File.file?(path)
            pattern = '/' + File.basename(path)
            path_rules[pattern] = [
              ["cache-control", "public,max-age=600"],
              ["forward", "static"]
            ]
          end
        end
      end

      path_rules.merge! fetch(:alice_path_rules, {})

      release.path_rules = path_rules
    end

  end # namespace "alice:release:create"

end
