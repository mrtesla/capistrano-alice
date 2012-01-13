
Capistrano::Configuration.instance(:must_exist).load do

  # happens before deploy:update_code
  task "alice:maintenance_mode:on" do
    on_rollback { find_and_execute_task("alice:maintenance_mode:off") }

  end

  # happens after deploy:restart
  task "alice:maintenance_mode:off" do

  end

end
