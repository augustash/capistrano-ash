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
      run "rm -Rf #{shared_path}/log"
      run "rm -Rf #{shared_path}/pids"
      run "rm -Rf #{shared_path}/system"
      
      # create shared directories
      run "mkdir -p #{shared_path}/uploads"
      run "mkdir -p #{shared_path}/cache"

      # set correct permissions
      run "chmod -R 755 #{shared_path}/*"
    end
  end
end