# Require our base library.
require 'ash/base'
require 'railsless-deploy'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # --------------------------------------------
  # Setting defaults
  # --------------------------------------------
  proc{_cset( :multisites, {"#{application}" => "#{application}"} )}
  set :drush_bin, "drush"

  # --------------------------------------------
  # Calling our Methods
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_local"
  after "deploy:finalize_update", "ash:fixperms"
  after "deploy:symlink", "drupal:symlink"
  after "drupal:symlink","drupal:protect"
  after "deploy", "drupal:clearcache"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup local files necessary for deployment"
    task :setup_local do
      # attempt to create files needed for proper deployment
      system("cp .htaccess htaccess.dist")
    end
    
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

      # set correct permissions
      run "chmod -R 777 #{shared_path}/*"
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
      # remove shared directories
      multisites.each_pair do |folder, url|
        if folder != url 
          run "mv #{latest_release}/sites/#{folder} #{latest_release}/sites/#{url}"
        end
        run "rm -Rf #{latest_release}/sites/#{url}/files"
      end
    end

    namespace :web do
      desc "Disable the application and show a message screen"
      task :disable, :roles => :web do
        multisites.each_pair do |folder, url|
          run "#{drush_bin} -l #{url} -r #{latest_release} vset --yes site_offline 1"
        end
      end

      desc "Enable the application and remove the message screen"
      task :enable, :roles => :web do
        multisites.each_pair do |folder, url|
          run "#{drush_bin} -l #{url} -r #{latest_release} vdel --yes site_offline"
        end
      end
    end
  end

  namespace :backup do
    desc "Perform a backup of database files"
    task :db, :roles => :db do
      if previous_release
        puts "Backing up the database now and putting dump file in the previous release directory"
        multisites.each_pair do |folder, url|
          # define the filename (include the current_path so the dump file will be within the directory)
          filename = "#{current_path}/#{folder}_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"
          # dump the database for the proper environment
          run "#{drush_bin} -l #{url} -r #{current_path} sql-dump | gzip -c --best > #{filename}"
        end
      else
        logger.important "no previous release to backup; backup of database skipped"
      end
    end
  end

  # --------------------------------------------
  # Drupal-specific methods
  # --------------------------------------------
  namespace :drupal do
   desc "Symlink shared directories"
   task :symlink, :roles => :web, :except => { :no_release => true } do
      multisites.each_pair do |folder, url|
        # symlinks the appropriate environment's settings.php file
        symlink_config_file
        
        run "ln -nfs #{shared_path}/#{url}/files #{latest_release}/sites/#{url}/files"
        run "#{drush_bin} -l #{url} -r #{current_path} vset --yes file_directory_path sites/#{url}/files"
      end
   end
   
   desc <<-DESC
    Symlinks the appropriate environment's settings file within the proper sites directory
    
    Assumes the environment's settings file will be in one of two formats:
        settings.<environment>.php    => new default
        settings.php.<environment>    => deprecated
   DESC
   task :symlink_config_file, :roles => :web, :except => { :no_release => true} do
     multisites.each_pair do |folder, url|
       drupal_app_site_dir = " #{latest_release}/sites/#{url}"
       
       case true
         when remote_file_exists?("#{drupal_app_site_dir}/settings.#{stage}.php")
           run "ln -nfs #{drupal_app_site_dir}/settings.#{stage}.php #{drupal_app_site_dir}/settings.php"
         when remote_file_exists?("#{drupal_app_site_dir}/settings.php.#{stage}")
           run "ln -nfs #{drupal_app_site_dir}/settings.php.#{stage} #{drupal_app_site_dir}/settings.php"
         else
           logger.important "Failed to symlink the settings.php file in #{drupal_app_site_dir} because an unknown pattern was used"
       end
     end
   end

   desc "Replace local database paths with remote paths"
   task :updatedb, :roles => :web, :except => { :no_release => true } do
     multisites.each_pair do |folder, url|
       run "#{drush_bin} -l #{url} -r #{current_path} sqlq \"UPDATE {files} SET filepath = REPLACE(filepath,'sites/#{folder}/files','sites/#{url}/files');\""
     end
   end

    desc "Clear all Drupal cache"
    task :clearcache, :roles => :web, :except => { :no_release => true } do
      multisites.each_pair do |folder, url|
        run "#{drush_bin} -l #{url} -r #{current_path} cache-clear all"
      end
    end
  
    desc "Protect system files"
    task :protect, :roles => :web, :except => { :no_release => true } do
      multisites.each_pair do |folder, url|
        run "chmod 644 #{latest_release}/sites/#{url}/settings.php*"
      end
    end
  end
end
