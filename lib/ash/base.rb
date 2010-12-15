# Capistrano2 differentiator
load 'deploy' if respond_to?(:namespace)
Dir['vendor/plugins/*/recipes/*.rb'].each { |plugin| load(plugin) }

# Required gems/libraries
require 'rubygems'
require 'railsless-deploy'
require 'ash/common'
require 'capistrano/ext/multistage'

# Bootstrap Capistrano instance
configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # Set default stages
  set :stages, %w(staging production)
  set :default_stge, "staging"

  # --------------------------------------------
  # Task chains
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_shared"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Default variables
  # --------------------------------------------
  # SSH
  set :user, proc{text_prompt("SSH username: ")}
  set :password, proc{Capistrano::CLI.password_prompt("SSH password for '#{user}':")}

  # Database
  set :dbuser, proc{text_prompt("Database username: ")}
  set :dbpass, proc{Capistrano::CLI.password_prompt("Database password for '#{dbuser}':")}
  set :dbname, proc{text_prompt("Database name: ")}

  # Source Control
  set :group_writable, false
  set :use_sudo, false
  set :scm, :subversion
  set :scm_verbose, true
  set :scm_username, proc{text_prompt("Subversion username: ")}
  set :scm_password, proc{Capistrano::CLI.password_prompt("Subversion password for '#{scm_username}': ")}
  set :keep_releases, 3
  set :deploy_via, :remote_cache
  set :copy_strategy, :checkout
  set :copy_compression, :bz2
  set :copy_exclude, [".svn", ".DS_Store", "*.sample", "LICENSE*", "Capfile",
    "config", "*.rb", "*.sql", "nbproject", "_template"]
  # phpMyAdmin version
  set :pma_version, "3.3.8"

  # show password requests on windows
  # (http://weblog.jamisbuck.org/2007/10/14/capistrano-2-1)
  default_run_options[:pty] = true

  # --------------------------------------------
  # Overloaded tasks
  # --------------------------------------------
  namespace :deploy do
    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      puts "STUB: Setup"
    end
  end

  # --------------------------------------------
  # Ash tasks
  # --------------------------------------------
  namespace :ash do
    desc "Set standard permissions for Ash servers"
    task :fixperms, :except => { :no_release => true } do
      # chmod the files and directories.
      sudo "find #{latest_release} -type d -exec chmod 755 {} \\;"
      sudo "find #{latest_release} -type f -exec chmod 644 {} \\;"
    end

    desc "Test: Task used to verify Capistrano is working. Prints operating system name."
    task :uname do
      run "uname -a"
    end

    desc "Test: Task used to verify Capistrano is working. Prints environment of Capistrano user."
    task :getpath do
      run "echo $PATH"
    end
  end

  # --------------------------------------------
  # PHP tasks
  # --------------------------------------------
  namespace :php do
    namespace :apc do
      desc "Disable the APC administrative panel"
      task :disable, :except => { :no_release => true } do
        run "rm #{current_path}/apc.php"
      end

      desc "Enable the APC administrative panel"
      task :enable, :except => { :no_release => true } do
        run "ln -s /usr/local/lib/php/apc.php #{current_path}/apc.php"
      end
    end
  end

  # --------------------------------------------
  # phpMyAdmin tasks
  # --------------------------------------------
  namespace :pma do
    desc "Disable the phpMyAdmin utility"
    task :disable,  :roles => :web, :except => { :no_release => true } do
      run "rm -f #{current_path}/pma"
    end

    desc "Enable the phpMyAdmin utility"
    task :enable, :roles => :web, :except => { :no_release => true } do
      run "ln -s #{shared_path}/pma #{current_path}/pma"
    end

    desc "Install phpMyAdmin utility"
    task :install, :roles => :web do
      # fetch PMA
      run "wget -O #{shared_path}/pma.tar.gz http://downloads.sourceforge.net/project/phpmyadmin/phpMyAdmin/#{pma_version}/phpMyAdmin-#{pma_version}-english.tar.gz"
      # decompress and install
      run "tar -zxf #{shared_path}/pma.tar.gz -C #{shared_path}"
      run "mv #{shared_path}/phpMyAdmin-#{pma_version}-english/ #{shared_path}/pma/"
      run "rm -f #{shared_path}/pma.tar.gz"
    end
  end

  # --------------------------------------------
  # Backup tasks
  # --------------------------------------------
  namespace :backup do
    desc "Perform a backup of web and database files"
    task :default do
      web
      db
    end

    desc "Perform a backup of web files"
    task :web, :roles => :web do
      puts "STUB: Backing up web server"
    end

    desc "Perform a backup of database files"
    task :db, :roles => :db do
      puts "STUB: Backing up db server"
    end
  end

end
