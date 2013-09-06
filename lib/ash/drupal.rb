# Require our base library.
require 'ash/base'
require 'railsless-deploy'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # --------------------------------------------
  # Deployment dependencies
  #
  #     $ cap <stage> deploy:check
  #
  # --------------------------------------------
  depend :remote, :command, 'drush'

  # --------------------------------------------
  # Setting defaults
  # --------------------------------------------
  proc{_cset( :multisites, {"#{application}" => "#{application}"} )}
  set :drush_bin, "drush"
  _cset :dump_options,    "" # blank options b/c of MYISAM engine (unless anyone knows options that should be included)


  # --------------------------------------------
  # Ubercart Files/Folders
  #   assumes ubercart files are located
  #   within a files/ubercart directory
  #   for each multisite
  # --------------------------------------------
  set :uc_root, "ubercart"
  set :uc_downloadable_products_root, "downloadable_products"
  set :uc_encryption_keys_root, "keys"

  # --------------------------------------------
  # Calling our Methods
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_local"
  after "deploy:finalize_update", "ash:fixperms"
  # after "deploy:create_symlink", "drupal:symlink"

  # workaround for issues with capistrano v2.13.3 and
  # before/after callbacks not firing for 'deploy:symlink'
  # or 'deploy:create_symlink'
  after "deploy", "drupal:symlink"
  after "drupal:symlink","drupal:protect"
  after "drupal:symlink", "drupal:clearcache"
  before "drupal:clearcache", "compass"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Overloaded Methods
  # --------------------------------------------
  namespace :deploy do
    desc "Setup local files necessary for deployment"
    task :setup_local do
      # attempt to create files needed for proper deployment
      system("cp .htaccess htaccess.dist") unless local_file_exists?("htaccess.dist")
    end

    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      # remove Capistrano specific directories
      try_sudo "rm -Rf #{shared_path}/log"
      try_sudo "rm -Rf #{shared_path}/pids"
      try_sudo "rm -Rf #{shared_path}/system"

      # create shared directories
      multisites.each_pair do |folder, url|
        try_sudo "mkdir -p #{shared_path}/#{url}/files"
      end

      # set correct permissions
      try_sudo "chmod -R 777 #{shared_path}/*"
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
      # remove shared directories
      multisites.each_pair do |folder, url|
        if folder != url
          try_sudo "mv #{latest_release}/sites/#{folder} #{latest_release}/sites/#{url}"
        end
        try_sudo "rm -Rf #{latest_release}/sites/#{url}/files"
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

  # --------------------------------------------
  # Remote/Local database migration tasks
  # --------------------------------------------
  namespace :db do
    task :local_export do
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "")

      system "#{mysqldump} #{dump_options} --opt -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} | gzip -c --best > #{db_local_name}.sql.gz"
    end

    desc "Create a compressed MySQL dumpfile of the remote database"
    task :remote_export, :roles => :db do
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "")

      run "#{mysqldump} #{dump_options} --opt -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} | gzip -c --best > #{deploy_to}/#{db_remote_name}.sql.gz"
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

        try_sudo "ln -nfs #{shared_path}/#{url}/files #{latest_release}/sites/#{url}/files"
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
        try_sudo "chmod 644 #{latest_release}/sites/#{url}/settings.php*"
      end
    end

    desc <<-DESC
      Secures the ubercart sensitive information (credit card encryption keys)
      and downloadable files by moving them from the sites file structure in
      the Drupal root (public) and moving them to the shared directory
    DESC
    namespace :ubercart do
      task :default, :roles => :web, :except => { :no_release => true } do
        # setup necessary directories within our shared directory
        setup_ubercart_shared

        # move the sites/*/files/downloadable_products
        # to the shared directory via rsync
        secure_downloadable_files

        # move the sites/*/files/keys
        # to the shared directory
        secure_encryption_key
      end

      desc <<-DESC
        Creates the ubercart directory within each multisites shared directory structure.

        Example:
            shared/abc/ubercart
            shared/xyz/ubercart
      DESC
      task :setup_ubercart_shared, :roles => :web, :except => { :no_release => true } do
        multisites.each_pair do |folder, url|
          try_sudo "mkdir -p #{shared_path}/#{url}/#{uc_root}"
        end
      end

      desc <<-DESC
        Moves downloadable files from the public directory (Drupal root) to the shared
        directories

        Example:
            sites/abc/files/ubercart/products
            sites/xyz/files/ubercart/downloadable_products

          are moved to:
            shared/abc/ubercart/products
            shared/xyz/ubercart/downloadable_products
      DESC
      task :secure_downloadable_files, :except => { :no_release => true } do
        # loop through the multisites and move files
        multisites.each_pair do |folder, url|
          try_sudo "mkdir -p #{shared_path}/#{url}/#{uc_root}/#{uc_downloadable_products_root}"

          ubercart_dir = "#{latest_release}/sites/#{url}/files/#{uc_root}/#{uc_downloadable_products_root}"

          case true
            when remote_dir_exists?("#{ubercart_dir}")
              try_sudo "rsync -rltDvzog #{ubercart_dir} #{shared_path}/#{url}/#{uc_root}/#{uc_downloadable_products_root}"
            else
              logger.important "Failed to rsync the ubercart downloadable products in #{ubercart_dir} because the directory doesn't exist"
          end


          # update the ubercart's database tracking of where the
          # root file path is for downloadable products. This should
          # be set as relative to the root of the drupal directory
          run "#{drush_bin} -l #{url} -r #{latest_release} vset --yes uc_file_base_dir ../../shared/#{url}/#{uc_root}/#{uc_downloadable_products_root}"
        end
      end

      desc <<-DESC
        Moves encryption key files from the public directory (Drupal root) to the shared
        directories

        Example:
            sites/abc/files/ubercart/keys
            sites/xyz/files/ubercart/keys

          are moved to:
            shared/abc/ubercart/keys
            shared/xyz/ubercart/keys
      DESC
      task :secure_encryption_key, :roles => :web, :except => { :no_release => true } do
        # loop through the multisites and move keys
        multisites.each_pair do |folder, url|
          try_sudo "mkdir -p #{shared_path}/#{url}/#{uc_root}/#{uc_encryption_keys_root}"

          # update the ubercart's database tracking of where the
          # root file path is for encryption keys. This should
          # be set as relative to the root of the drupal directory
          run "#{drush_bin} -l #{url} -r #{latest_release} vset --yes uc_credit_encryption_path ../../shared/#{url}/#{uc_root}/#{uc_encryption_keys_root}"
        end
      end
    end
  end
end
