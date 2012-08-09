# Require our base drupal library
require 'ash/drupal'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      # remove Capistrano specific directories
      run "rm -Rf #{shared_path}/log"
      run "rm -Rf #{shared_path}/pids"
      run "rm -Rf #{shared_path}/system"

      # create shared directories
      multisites.each_pair do |folder, url|
        run "mkdir -p #{shared_path}/#{url}/files"
      end

      # set correct permissions for a shared hosting environment
      set_perms_dirs("#{shared_path}")
    end
  end
end