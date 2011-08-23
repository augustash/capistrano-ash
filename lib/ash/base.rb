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
  set :pma_version,       "3.3.8"

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
  end

end
