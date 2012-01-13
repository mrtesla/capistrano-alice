
Capistrano::Configuration.instance(:must_exist).load do

  namespace :alice do
    namespace :maintenance do

      # happens before deploy:update_code
      task :on do
        on_rollback { find_and_execute_task("alice:maintenance:off") }

        path = "/api_v1/applications/#{alice_config.application}/maintenance.json"
        Net::HTTP.start(alice_config.alice_host, alice_config.alice_port) do |http|
          request = Net::HTTP::Post.new(path)
          request.body = Yajl::Encoder.encode({})
          request.content_type = "application/json"
          request['Accepts'] = "application/json"
          response = http.request(request)
        end
      end

      # happens after deploy:restart
      task :off do
        path = "/api_v1/applications/#{alice_config.application}/maintenance.json"
        Net::HTTP.start(alice_config.alice_host, alice_config.alice_port) do |http|
          request = Net::HTTP::Delete.new(path)
          request.body = Yajl::Encoder.encode({})
          request.content_type = "application/json"
          request['Accepts'] = "application/json"
          response = http.request(request)
        end
      end

    end
  end

end
