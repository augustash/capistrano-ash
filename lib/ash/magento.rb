# Required base libraries
require 'ash/base'
require 'railsless-deploy'

# Bootstrap Capistrano instance
configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do
  # --------------------------------------------
  # Task chains
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_local"
#  after "deploy:setup_shared", "pma:install"
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
      system("cp .htaccess htaccess.dist")
      system("cp app/etc/local.xml app/etc/local.xml.staging")
      system("cp app/etc/local.xml app/etc/local.xml.production")
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
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
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
      run "chmod 400 #{latest_release}/pear" if remote_file_exists?("#{latest_release}/pear")
      run "chmod 400 #{latest_release}/mage" if remote_file_exists?("#{latest_release}/mage")
      run "chmod o+w #{latest_release}/app/etc"
    end

    namespace :web do
      desc "Disable the application and show a message screen"
      task :disable, :roles => :web, :except => { :no_release => true } do
        run "touch #{current_path}/maintenance.flag"
      end

      desc "Enable the application and remove the message screen"
      task :enable, :roles => :web, :except => { :no_release => true } do
        run "rm #{current_path}/maintenance.flag"
      end
    end
  end

  # --------------------------------------------
  # Magento specific tasks
  # --------------------------------------------
  namespace :magento do
    desc "Set appropriate configuration values for the stage"
    task :activate_config, :roles => :web, :except => { :no_release => true } do
      case true
      when remote_file_exists?("#{latest_release}/app/etc/local.#{stage}.xml")
        run "cp -f #{latest_release}/app/etc/local.#{stage}.xml #{latest_release}/app/etc/local.xml"
      when remote_file_exists?("#{latest_release}/app/etc/local.xml.#{stage}")
        run "cp -f #{latest_release}/app/etc/local.xml.#{stage} #{latest_release}/app/etc/local.xml"
      end
    end

    desc "Symlink shared directories"
    task :symlink, :roles => :web, :except => { :no_release => true } do
      run "ln -nfs #{shared_path}/includes #{latest_release}/includes"
      run "ln -nfs #{shared_path}/media #{latest_release}/media"
      run "ln -nfs #{shared_path}/sitemap #{latest_release}/sitemap"
      run "ln -nfs #{shared_path}/var #{latest_release}/var"
    end

    desc "Purge Magento cache directory"
    task :purge_cache, :roles => :web, :except => { :no_release => true } do
      sudo "rm -Rf #{shared_path}/var/cache/*"
    end

    desc "Watch Magento system log"
    task :watch_logs, :roles => :web, :except => { :no_release => true } do
      run "tail -f #{shared_path}/var/log/system.log" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}"
        break if stream == :err
      end
    end

    desc "Watch Magento exception log"
    task :watch_exceptions, :roles => :web, :except => { :no_release => true } do
      run "tail -f #{shared_path}/var/log/exception.log" do |channel, stream, data|
        puts  # for an extra line break before the host name
        puts "#{channel[:host]}: #{data}"
        break if stream == :err
      end
    end
  end
  
  # --------------------------------------------
  # Override the base.rb backup tasks
  # --------------------------------------------
  namespace :backup do
    desc "Perform a backup of ONLY database SQL files"
    task :default do
      db
      cleanup
    end

    desc "Perform a backup of database files"
    task :db, :roles => :db do
      if previous_release
        puts "Backing up the database now and putting dump file in the #{stage}/backups directory"

        # define the filename (dump the SQL file directly to the backups directory)
        filename = "#{backups_path}/#{dbname}_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"

        # dump the database for the proper environment
        run "#{mysldump} #{dump_options} -u #{dbuser} -p #{dbname} | gzip -c --best > #{filename}" do |ch, stream, out|
          ch.send_data "#{dbpass}\n" if out =~ /^Enter password:/
        end
      else
        logger.important "no previous release to backup to; backup of database skipped"
      end
    end
  end

end
