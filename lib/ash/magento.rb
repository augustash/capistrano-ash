# Required base libraries
require 'ash/base'

# Bootstrap Capistrano instance
configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Task chains
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_local"
  after "deploy:setup_shared", "pma:install"
  after "deploy:finalize_update", "magento:activate_config"
  after "deploy:symlink", "magento:symlink"
  after "deploy", "magento:purge_cache"

  # --------------------------------------------
  # Overloaded tasks
  # --------------------------------------------
  namespace :deploy do
    desc "Setup local files necessary for deployment"
    task :setup_local do
      # attempt to create files needed for proper deployment
      system("touch app/etc/local.xml.staging app/etc/local.xml.production")
    end
    
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
      run "chmod 777 #{shared_path}/*"
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :except => { :no_release => true } do
      # synchronize media directory with shared data
      sudo "rsync -rltDvzog #{latest_release}/media/ #{shared_path}/media/"
      sudo "chmod -R 777 #{shared_path}/media/"
      
      # remove directories that will be shared
      run "rm -Rf #{latest_release}/includes"
      run "rm -Rf #{latest_release}/media"
      run "rm -Rf #{latest_release}/sitemap"
      run "rm -Rf #{latest_release}/var"

      # set the file and directory permissions
      ash.fixperms
      run "chmod 400 #{latest_release}/pear"
      run "chmod o+w #{latest_release}/app/etc"
    end

    namespace :web do
      desc "Disable the application and show a message screen"
      task :disable, :except => { :no_release => true } do
        run "touch #{current_path}/maintenance.flag"
      end

      desc "Enable the application and remove the message screen"
      task :enable, :except => { :no_release => true } do
        run "rm #{current_path}/maintenance.flag"
      end
    end
  end

  # --------------------------------------------
  # Magento specific tasks
  # --------------------------------------------
  namespace :magento do
    desc "Set appropriate configuration values for the stage"
    task :activate_config, :except => { :no_release => true } do
      run "cp -f #{latest_release}/app/etc/local.xml.#{stage} #{latest_release}/app/etc/local.xml"
    end

    desc "Symlink shared directories"
    task :symlink, :except => { :no_release => true } do
      run "ln -nfs #{shared_path}/includes #{current_release}/includes"
      run "ln -nfs #{shared_path}/media #{current_release}/media"
      run "ln -nfs #{shared_path}/sitemap #{current_release}/sitemap"
      run "ln -nfs #{shared_path}/var #{current_release}/var"
    end

    desc "Purge Magento cache directory"
    task :purge_cache, :except => { :no_release => true } do
      sudo "rm -Rf #{shared_path}/var/cache/*"
    end

    desc "Watch Magento system log"
    task :watch_logs, :except => { :no_release => true } do      
      run "tail -f #{shared_path}/var/log/system.log" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}" 
        break if stream == :err    
      end
    end

    desc "Watch Magento exception log"
    task :watch_exceptions, :except => { :no_release => true } do
      run "tail -f #{shared_path}/var/log/exception.log" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}" 
        break if stream == :err    
      end
    end
  end

  # --------------------------------------------
  # Custom tasks
  # --------------------------------------------

  # update core_config_data; set value = "domain" where scope_id = 0 and path = "web/unsecure/base_url"

end