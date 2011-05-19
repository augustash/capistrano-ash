# Require our base drupal library
require 'ash/zend_doctrine'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc<<-DESC
      Setup shared directories and permissions after initial setup \
      for a shared hosting enviroment
    DESC
    task :setup_shared, :roles => :web, :except => { :no_release => true } do
      run<<-CMD 
        mkdir -p #{shared_path}/var &&
        mkdir -p #{shared_path}/var/logs &&
        mkdir -p #{shared_path}/var/cache && 
        mkdir -p #{shared_path}/var/sessions &&
        mkdir -p #{shared_path}/system
      CMD
      try_sudo "chmod -R 755 #{shared_path}/*"
    end
  end
end