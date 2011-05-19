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
  proc{_cset( :multisites, {"default" => "#{application}"} )}
  set :drush_bin, "drush"

  # --------------------------------------------
  # Calling our Methods
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_shared"
  after "deploy:finalize_update", "ash:fixperms"
  after "ash:fixperms", "drupal:protect"
  after "deploy:symlink", "drupal:symlink"
  after "deploy", "drupal:clearcache"
  after "deploy", "drupal:htaccess"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared, :roles => :web do
      # remove Capistrano specific directories
      run<<-CMD
        rm -Rf #{shared_path}/log &&
        rm -Rf #{shared_path}/pids &&
        rm -Rf #{shared_path}/system
      CMD

      # create shared directories
      multisites.each_pair do |folder, url|
        run "mkdir -p #{shared_path}/#{url}/files"
      end

      # set correct permissions
      run "chmod -R 777 #{shared_path}/*"
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :except => { :no_release => true } do
      # remove shared directories
      multisites.each_pair do |folder, url|
        run "mv #{latest_release}/sites/#{folder} #{latest_release}/sites/#{url}"
        run "rm -Rf #{latest_release}/sites/#{url}/files"
      end
    end

    namespace :web do
      desc "Disable the application and show a message screen"
      task :disable do
        multisites.each_pair do |folder, url|
          run "#{drush_bin} -l #{url} -r #{latest_release} vset --yes site_offline 1"
        end
      end

      desc "Enable the application and remove the message screen"
      task :enable do
        multisites.each_pair do |folder, url|
          run "#{drush_bin} -l #{url} -r #{latest_release} vdel --yes site_offline"
        end
      end
    end
  end

  namespace :backup do
    desc "Perform a backup of database files"
    task :db, :roles => :db do
      puts "Backing up the database now and putting dump file in the previous release directory"
      multisites.each_pair do |folder, url|
        # define the filename (include the current_path so the dump file will be within the directory)
        filename = "#{current_path}/#{folder}_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"
        # dump the database for the proper environment
        run "#{drush_bin} -l #{url} -r #{current_path} sql-dump | gzip -c --best > #{filename}"
      end
    end
  end

  # --------------------------------------------
  # Drupal-specific methods
  # --------------------------------------------
  namespace :drupal do
   desc "Symlink shared directories"
   task :symlink, :except => { :no_release => true } do
      multisites.each_pair do |folder, url|
        run<<-CMD
          ln -nfs #{shared_path}/#{url}/files #{latest_release}/sites/#{url}/files &&
          ln -nfs #{latest_release}/sites/#{url}/settings.php.#{stage} #{latest_release}/sites/#{url}/settings.php &&
          #{drush_bin} -l #{url} -r #{current_path} vset --yes file_directory_path sites/#{url}/files
        CMD
      end
   end

   desc "Replace local database paths with remote paths"
   task :updatedb, :except => { :no_release => true } do
     multisites.each_pair do |folder, url|
       run "#{drush_bin} -l #{url} -r #{current_path} sqlq \"UPDATE {files} SET filepath = REPLACE(filepath,'sites/#{folder}/files','sites/#{url}/files');\""
     end
   end

    desc "Clear all Drupal cache"
    task :clearcache, :except => { :no_release => true } do
      multisites.each_pair do |folder, url|
        run "#{drush_bin} -l #{url} -r #{current_path} cache-clear all"
      end
    end
  
    desc "Protect system files"
    task :protect, :except => { :no_release => true } do
      multisites.each_pair do |folder, url|
        run "chmod 644 #{latest_release}/sites/#{url}/settings.php*"
      end
    end
  
    desc 'Copy over htaccess file'
    task :htaccess do
      run "cp #{latest_release}/htaccess.dist #{latest_release}/.htaccess"
    end
  end
end
