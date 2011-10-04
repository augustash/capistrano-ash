# Capistrano2 differentiator
load 'deploy' if respond_to?(:namespace)
Dir['vendor/plugins/*/recipes/*.rb'].each { |plugin| load(plugin) }

# Required gems/libraries
require 'rubygems'
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
  after "deploy:setup_shared", "deploy:setup_backup"
  after "deploy:finalize_update", "ash:htaccess"
  after "deploy", "deploy:cleanup"

  # --------------------------------------------
  # Default variables
  # --------------------------------------------
  # SSH
  set :user,              proc{text_prompt("SSH username: ")}
  set :password,          proc{Capistrano::CLI.password_prompt("SSH password for '#{user}':")}

  # Database
  set :dbuser,            proc{text_prompt("Database username: ")}
  set :dbpass,            proc{Capistrano::CLI.password_prompt("Database password for '#{dbuser}':")}
  set :dbname,            proc{text_prompt("Database name: ")}

  # Source Control
  set :group_writable,    false
  set :use_sudo,          false
  set :scm,               :subversion
  set :scm_verbose,       true
  set :scm_username,      proc{text_prompt("Subversion username: ")}
  set :scm_password,      proc{Capistrano::CLI.password_prompt("Subversion password for '#{scm_username}': ")}
  set :keep_releases,     3
  set :deploy_via,        :remote_cache
  set :copy_strategy,     :checkout
  set :copy_compression,  :bz2
  set :copy_exclude,      [".svn", ".DS_Store", "*.sample", "LICENSE*", "Capfile",
    "RELEASE*", "*.rb", "*.sql", "nbproject", "_template"]

  # phpMyAdmin version
  set :pma_version,       "3.4.5"

  # Backups Path
  _cset(:backups_path)    { File.join(deploy_to, "backups") }
  _cset(:backups)         { capture("ls -x #{backups_path}", :except => { :no_release => true }).split.sort }

  # Define which files or directories you want to exclude from being backed up
  _cset(:backup_exclude)  { [] }
  set :exclude_string,    ''

  # Define the default number of backups to keep
  set :keep_backups,      10

  # show password requests on windows
  # (http://weblog.jamisbuck.org/2007/10/14/capistrano-2-1)
  default_run_options[:pty] = true
  
  # Database migration settings
  set :db_local_host, "192.168.16.116"
  set :db_local_user, "developer"
  set :db_local_name, proc{text_prompt("Local database name: #{db_local_name}: ")}
  set :db_local_pass, proc{text_prompt("Local database password for: #{db_local_user}: ")}
  set :db_remote_user, proc{text_prompt("Remote database user: #{db_remote_user}: ")}
  set :db_remote_pass, proc{text_prompt("Remote database password for: #{db_remote_user}: ")}
  set :db_remote_name, proc{text_prompt("Remote database name: #{db_remote_name}: ")}
  set :db_remote_host, "localhost"

  # Database replacement values
  # Format: local => remote
  set :db_regex_hash, {
  }

  # --------------------------------------------
  # Overloaded tasks
  # --------------------------------------------
  namespace :deploy do
    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      puts "STUB: Setup"
    end

    desc "Setup backup directory for database and web files"
    task :setup_backup, :except => { :no_release => true } do
      run "#{try_sudo} mkdir -p #{backups_path} && #{try_sudo} chmod g+w #{backups_path}"
    end
  end

  # --------------------------------------------
  # Ash tasks
  # --------------------------------------------
  namespace :ash do
    desc "Set standard permissions for Ash servers"
    task :fixperms, :roles => :web, :except => { :no_release => true } do
      # chmod the files and directories.
      try_sudo "find #{latest_release} -type d -exec chmod 755 {} \\;"
      try_sudo "find #{latest_release} -type f -exec chmod 644 {} \\;"
    end

    desc "Test: Task used to verify Capistrano is working. Prints operating system name."
    task :uname do
      run "uname -a"
    end

    desc "Test: Task used to verify Capistrano is working. Prints environment of Capistrano user."
    task :getpath do
      run "echo $PATH"
    end

    desc 'Copy distribution htaccess file'
    task :htaccess, :roles => :web do
      run "mv #{latest_release}/htaccess.dist #{latest_release}/.htaccess" if
        remote_file_exists?("#{latest_release}/htaccess.dist")
    end
  end

  # --------------------------------------------
  # PHP tasks
  # --------------------------------------------
  namespace :php do
    namespace :apc do
      desc "Disable the APC administrative panel"
      task :disable, :roles => :web, :except => { :no_release => true } do
        run "rm #{current_path}/apc.php"
      end

      desc "Enable the APC administrative panel"
      task :enable, :roles => :web, :except => { :no_release => true } do
        run "ln -s /usr/local/lib/php/apc.php #{current_path}/apc.php"
      end
    end
  end

  # --------------------------------------------
  # Remote/Local database migration tasks
  # --------------------------------------------
  namespace :db do
    desc "Migrate remote application database to local server"
    task :to_local do
      remote_export
      remote_download
      local_import
    end

    desc "Migrate local application database to remote server"
    task :to_remote do
      local_export
      local_upload
      remote_import
    end

    desc "Handles importing a MySQL database dump file. Uncompresses the file, does regex replacements, and imports."
    task :local_import do
      # check for compressed file and decompress
      if local_file_exists?("#{db_remote_name}.sql.gz")
        system "gunzip -f #{db_remote_name}.sql.gz"
      end

      if local_file_exists?("#{db_remote_name}.sql")
        # run through replacements on SQL file
        db_regex_hash.each_pair do |local, remote|
          system "perl -pi -e 's/#{remote}/#{local}/g' #{db_remote_name}.sql"
        end
        # import into database
        system "mysql -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} < #{db_remote_name}.sql"
        # remove used file
        run "rm -f #{deploy_to}/#{db_remote_name}.sql.gz"
        system "rm -f #{db_remote_name}.sql"
      end
    end

    task :local_export do
      system "mysqldump --opt -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} | gzip -c --best > #{db_local_name}.sql.gz"
    end

    desc "Upload locally created MySQL dumpfile to remote server via SCP"
    task :local_upload do
      upload "#{db_local_name}.sql.gz", "#{deploy_to}/#{db_local_name}.sql.gz", :via => :scp
    end

    desc "Handles importing a MySQL database dump file. Uncompresses the file, does regex replacements, and imports."
    task :remote_import, :roles => :db do
      # check for compressed file and decompress
      if remote_file_exists?("#{deploy_to}/#{db_local_name}.sql.gz")
        run "gunzip -f #{deploy_to}/#{db_local_name}.sql.gz"
      end

      if remote_file_exists?("#{deploy_to}/#{db_local_name}.sql")
        # run through replacements on SQL file
        db_regex_hash.each_pair do |local, remote|
          run "perl -pi -e 's/#{local}/#{remote}/g' #{deploy_to}/#{db_local_name}.sql"
        end
        # import into database
        run "mysql -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} < #{deploy_to}/#{db_local_name}.sql"
        # remove used file
        run "rm -f #{deploy_to}/#{db_local_name}.sql"
        system "rm -rf #{db_local_name}.sql.gz"
      end
    end

    desc "Create a compressed MySQL dumpfile of the remote database"
    task :remote_export, :roles => :db do
      run "mysqldump --opt -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} | gzip -c --best > #{deploy_to}/#{db_remote_name}.sql.gz"
    end

    desc "Download remotely created MySQL dumpfile to local machine via SCP"
    task :remote_download do
      download "#{deploy_to}/#{db_remote_name}.sql.gz", "#{db_remote_name}.sql.gz", :via => :scp
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
      db
      web
    end

    desc <<-DESC
      Requires the rsync package to be installed.

      Performs a file-level backup of the application and any assets \
      from the shared directory that have been symlinked into the \
      applications root or sub-directories.

      You can specify which files or directories to exclude from being \
      backed up (i.e., log files, sessions, cache) by setting the \
      :backup_exclude variable
          set(:backup_exclude) { [ "var/", "tmp/", logs/debug.log ] }
    DESC
    task :web, :roles => :web do
      if previous_release
        puts "Backing up web files (user uploaded content and previous release)"

        if !backup_exclude.nil? && !backup_exclude.empty?
          logger.debug "processing backup exclusions..."
          backup_exclude.each do |pattern|
            exclude_string << "--exclude '#{pattern}' "
          end
          logger.debug "Exclude string = #{exclude_string}"
        end

        # Copy the previous release to the /tmp directory
        logger.debug "Copying previous release to the /tmp/#{release_name} directory"
        run "rsync -avzrtpL #{exclude_string} #{current_path}/ /tmp/#{release_name}/"
        # create the tarball of the previous release
        set :archive_name, "release_B4_#{release_name}.tar.gz"
        logger.debug "Creating a Tarball of the previous release in #{backups_path}/#{archive_name}"
        run "cd /tmp && tar -cvpf - ./#{release_name}/ | gzip -c --best > #{backups_path}/#{archive_name}"

        # remove the the temporary copy
        logger.debug "Removing the tempory copy"
        run "rm -rf /tmp/#{release_name}"
      else
        logger.important "no previous release to backup; backup of files skipped"
      end
    end

    desc "Perform a backup of database files"
    task :db, :roles => :db do
      if previous_release
        puts "Backing up the database now and putting dump file in the previous release directory"
        # define the filename (include the current_path so the dump file will be within the directory)
        filename = "#{current_path}/#{dbname}_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"
        # dump the database for the proper environment
        run "mysqldump -u #{dbuser} -p #{dbname} | gzip -c --best > #{filename}" do |ch, stream, out|
            ch.send_data "#{dbpass}\n" if out =~ /^Enter password:/
        end
      else
        logger.important "no previous release to backup to; backup of database skipped"
      end
    end

    desc <<-DESC
      Clean up old backups. By default, the last 10 backups are kept on each \
      server (though you can change this with the keep_backups variable). All \
      other backups are removed from the servers. By default, this \
      will use sudo to clean up the old backups, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead.
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_backups, 10).to_i
      if count >= backups.length
        logger.important "no old backups to clean up"
      else
        logger.info "keeping #{count} of #{backups.length} backups"

        archives = (backups - backups.last(count)).map { |backup|
          File.join(backups_path, backup) }.join(" ")

        try_sudo "rm -rf #{archives}"
      end
    end
  end

  # --------------------------------------------
  # Remote File/Directory test tasks
  # --------------------------------------------
  namespace :remote do
    namespace :file do
      desc "Test: Task to test existence of missing file"
      task :missing do
        if remote_file_exists?('/dev/mull')
          logger.info "FAIL - Why does the '/dev/mull' path exist???"
        else
          logger.info "GOOD - Verified the '/dev/mull' path does not exist!"
        end
      end

      desc "Test: Task used to test existence of a present file"
      task :exists do
        if remote_file_exists?('/dev/null')
          logger.info "GOOD - Verified the '/dev/null' path exists!"
        else
          logger.info "FAIL - WHAT happened to the '/dev/null' path???"
        end
      end
    end

    namespace :dir do
      desc "Test: Task to test existence of missing dir"
      task :missing do
        if remote_dir_exists?('/etc/fake_dir')
          logger.info "FAIL - Why does the '/etc/fake_dir' dir exist???"
        else
          logger.info "GOOD - Verified the '/etc/fake_dir' dir does not exist!"
        end
      end

      desc "Test: Task used to test existence of an existing directory"
      task :exists do
        if remote_dir_exists?('/etc')
          logger.info "GOOD - Verified the '/etc' dir exists!"
        else
          logger.info "FAIL - WHAT happened to the '/etc' dir???"
        end
      end
    end
  end
end
