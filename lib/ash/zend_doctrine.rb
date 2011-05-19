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
      run "mkdir -p #{shared_path}/var"
      run "mkdir -p #{shared_path}/var/logs"
      run "mkdir -p #{shared_path}/var/cache"
      run "mkdir -p #{shared_path}/var/sessions"
      run "mkdir -p #{shared_path}/system"
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
      run "ln -nfs #{shared_path}/var #{current_release}/var"
      run "ln -nfs #{shared_path}/system #{current_release}/public/system"
      run "mv #{current_release}/application/configs/application.ini.dist #{current_release}/application/configs/application.ini"
      run "ln -nfs #{current_release}/application/Application.#{stage}.php #{current_release}/application/Application.php"
      run "mv #{current_release}/public/htaccess.#{stage} #{current_release}/public/.htaccess"
      run "cp #{current_release}/scripts/doctrine-cli.#{stage} #{current_release}/scripts/doctrine-cli"
      
      
      try_sudo "chmod +x #{current_release}/scripts/doctrine-cli"
      
      # remove the example or other environment example files
      run "rm -f #{current_release}/scripts/doctrine-cli.dist"
      run "rm -f #{current_release}/scripts/doctrine-cli.staging"
      run "rm -f #{current_release}/scripts/doctrine-cli.production"
      run "rm -f #{current_release}/application/Application.example.php"
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
