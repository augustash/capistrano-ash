# Required base libraries
require 'ash/magento'

# Bootstrap Capistrano instance
configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Default variables
  # --------------------------------------------
  set :scm_username, "remotesvn"
  
  # --------------------------------------------
  # Task chains
  # --------------------------------------------

  # --------------------------------------------
  # Overloaded tasks
  # --------------------------------------------
  namespace :deploy do    
    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      # remove Capistrano specific directories
      run "rm -Rf #{shared_path}/log"
      run "rm -Rf #{shared_path}/pids"
      run "rm -Rf #{shared_path}/system"

      # create shared directories
      run "mkdir -p #{shared_path}/includes"
      run "mkdir -p #{shared_path}/media"
      run "mkdir -p #{shared_path}/sitemap"
      run "mkdir -p #{shared_path}/var"

      # set correct permissions
      run "chmod 755 #{shared_path}/*"
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :except => { :no_release => true } do
      # synchronize media directory with shared data
      run "rsync -rltDvzog #{latest_release}/media/ #{shared_path}/media/"
      
      # put ".htaccess" in place
      run "mv #{latest_release}/htaccess.dist #{latest_release}/.htaccess"

      # remove directories that will be shared
      run "rm -Rf #{latest_release}/includes"
      run "rm -Rf #{latest_release}/media"
      run "rm -Rf #{latest_release}/sitemap"
      run "rm -Rf #{latest_release}/var"

      # set the file and directory permissions
      ash.fixperms
    end
  end
  
  # --------------------------------------------
  # Overloaded Ash tasks
  # --------------------------------------------
  namespace :ash do
    desc "Set standard permissions for Ash servers"
    task :fixperms, :except => { :no_release => true } do
      # chmod the files and directories.
      run "find #{latest_release} -type d -exec chmod 755 {} \\;"
      run "find #{latest_release} -type f -exec chmod 644 {} \\;"
    end
  end
end
