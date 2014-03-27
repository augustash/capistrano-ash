# Require our base library.
require 'ash/base'
require 'railsless-deploy'


configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # try_sudo configuration
  # --------------------------------------------
  set :use_sudo, true                 # allow try_sudo methods to actually run via sudo
  # set(:admin_runner) {"#{user}"}    # specify the :admin_runner if you need to run it as another user other than root

  # Clear out the default prompt (i.e., `sudo -p 'sudo password: '`) to fall back
  # to just using `sudo` due to the concatenation in the sudo method.
  #
  # This assumes that you have set up your SSH user to have passwordless sudo
  # setup for common commands (e.g., chmod, rm, rsync, etc.)
  #
  # (see: https://github.com/capistrano/capistrano/blob/legacy-v2/lib/capistrano/configuration/actions/invocation.rb#L229-L237)
  set :sudo_prompt, ''

  # --------------------------------------------
  # Calling our Methods
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_shared"
  after "deploy:finalize_update", "ash:fixperms"

  # workaround for issues with capistrano v2.13.3 and
  # before/after callbacks not firing for 'deploy:symlink'
  # or 'deploy:create_symlink'
  after "deploy:create_symlink", "zend:symlink"
  after "zend:symlink", "compass"
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
    task :symlink, :roles => :web, :except => { :no_release => true } do
      run "ln -nfs #{shared_path}/var #{latest_release}/var"
      run "ln -nfs #{shared_path}/system #{latest_release}/public/system"
      run "mv #{latest_release}/application/configs/application.ini.dist #{latest_release}/application/configs/application.ini"
      run "ln -nfs #{latest_release}/application/Application.#{stage}.php #{latest_release}/application/Application.php"
      run "mv #{latest_release}/public/htaccess.#{stage} #{latest_release}/public/.htaccess"
      run "cp #{latest_release}/scripts/doctrine-cli.#{stage} #{latest_release}/scripts/doctrine-cli"


      try_sudo "chmod +x #{latest_release}/scripts/doctrine-cli"

      # remove the example or other environment example files
      run "rm -f #{latest_release}/scripts/doctrine-cli.dist"
      run "rm -f #{latest_release}/scripts/doctrine-cli.staging"
      run "rm -f #{latest_release}/scripts/doctrine-cli.production"
      run "rm -f #{latest_release}/application/Application.example.php"
    end
  end

  namespace :doctrine do
    desc "Run Doctrine Migrations"
    task :migrate, :roles => :web, :except => { :no_release => true } do
      puts "Running Doctrine Migrations..."
      run "cd #{latest_release} && ./scripts/doctrine-cli migrate"
    end
  end
end
