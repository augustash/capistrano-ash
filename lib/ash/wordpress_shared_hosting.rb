# Require our base drupal library
require 'ash/wordpress'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared, :roles => :web do
      # remove Capistrano specific directories
      run<<-CMD
        rm -Rf #{shared_path}/log &&
        rm -Rf #{shared_path}/pids &&
        rm -Rf #{shared_path}/system
      CMD
      
      # create shared directories
      run<<-CMD
        mkdir -p #{shared_path}/uploads &&
        mkdir -p #{shared_path}/cache
      CMD

      # set correct permissions
      run "chmod -R 755 #{shared_path}/*"
    end
  end
end