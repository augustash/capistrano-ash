# Require our base library.
require 'ash/base'
require 'railsless-deploy'


configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Calling our Methods
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_shared"
  after "deploy:finalize_update", "ash:fixperms"
  after "deploy:symlink", "zend:symlink"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup shared directories and permissions after initial setup"
    task :setup_shared, :roles => :web, :except => { :no_release => true } do
      run<<-CMD 
        mkdir -p #{shared_path}/var &&
        mkdir -p #{shared_path}/var/logs &&
        mkdir -p #{shared_path}/var/cache && 
        mkdir -p #{shared_path}/var/sessions &&
        mkdir -p #{shared_path}/system
      CMD
      try_sudo "chmod -R 777 #{shared_path}/*"
    end
    
    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
      # remove shared directories
      run "rm -Rf #{latest_release}/var"
      run "rm -Rf #{latest_release}/public/system"
    end
  end
  
  namespace :zend do
    desc "Symlink shared directories"
    task :symlink, :except => { :no_release => true } do
      run<<-CMD
        ln -nfs #{shared_path}/var #{current_release}/var &&
        ln -nfs #{shared_path}/system #{current_release}/public/system &&
        mv #{current_release}/application/configs/application.ini.dist #{current_release}/application/configs/application.ini &&
        ln -nfs #{current_release}/application/Application.#{stage}.php #{current_release}/application/Application.php &&
        mv #{current_release}/public/htaccess.#{stage} #{current_release}/public/.htaccess &&
        cp #{current_release}/scripts/doctrine-cli.#{stage} #{current_release}/scripts/doctrine-cli
      CMD
      
      try_sudo "chmod +x #{current_release}/scripts/doctrine-cli"
      
      # remove the example or other environment example files
      run<<-CMD
        rm -f #{current_release}/scripts/doctrine-cli.dist &&
        rm -f #{current_release}/scripts/doctrine-cli.staging &&
        rm -f #{current_release}/scripts/doctrine-cli.production &&
        rm -f #{current_release}/application/Application.example.php
      CMD
    end
  end
  
  namespace :doctrine do
    desc "Run Doctrine Migrations"
    task :migrate, :except => { :no_release => true } do
      puts "Running Doctrine Migrations..."
      run "cd #{current_release} && ./scripts/doctrine-cli migrate"
    end
  end
end
