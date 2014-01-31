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
  set :default_stage, "staging"

  # --------------------------------------------
  # Task chains
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_shared"
  after "deploy:setup_shared", "deploy:setup_backup"
  after "deploy:finalize_update", "ash:htaccess"
  after "deploy", "deploy:cleanup"
  after "deploy", "seo:robots"

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
  _cset :mysqldump,       "mysqldump"
  _cset :dump_options,    "--single-transaction --create-options --quick --triggers --routines --force --opt --skip-lock-tables"
  _cset :ignore_tables,   []

  # Source Control
  # set :group_writable,    false
  set :use_sudo,          false
  set :scm,               :git
  set :git_enable_submodules, 1 if fetch(:scm, :git)
  set :scm_verbose,       true
  set :scm_username,      proc{text_prompt("Subversion username: ")}
  set :scm_password,      proc{Capistrano::CLI.password_prompt("Subversion password for '#{scm_username}': ")}
  set :keep_releases,     3
  set :deploy_via,        :remote_cache
  set :copy_strategy,     :checkout
  set :copy_compression,  :bz2
  set :copy_exclude,      [".svn", ".git*", ".DS_Store", "*.sample", "LICENSE*", "Capfile",
    "RELEASE*", "config/deploy", "*.rb", "*.sql", "nbproject", "_template"]

  # phpMyAdmin version
  set :pma_version,       "3.4.5"

  # FIX capistrano 2.15.4+ use of `try_sudo` with capture commands (shouldn't need sudo for `ls` and `cat` commands)
  set(:releases) { capture("ls -x #{releases_path}", :except => { :no_release => true }).split.sort }
  set(:current_revision) { capture("cat #{current_path}/REVISION", :except => { :no_release => true }).chomp }
  set(:latest_revision) { capture("cat #{current_release}/REVISION", :except => { :no_release => true }).chomp }
  set(:previous_revision) { capture("cat #{previous_release}/REVISION", :except => { :no_release => true }).chomp if previous_release }


  # Backups Path
  _cset(:backups_path)      { File.join(deploy_to, "backups") }
  _cset(:tmp_backups_path)  { File.join("#{backups_path}", "tmp") }
  _cset(:backups)           { capture("ls -x #{backups_path}", :except => { :no_release => true }).split.sort }

  # Define which files or directories you want to exclude from being backed up
  _cset(:backup_exclude)  { [] }
  set :exclude_string,    ''

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
    desc <<-DESC
      Prepares one or more servers for deployment. Before you can use any \
      of the Capistrano deployment tasks with your project, you will need to \
      make sure all of your servers have been prepared with `cap deploy:setup'. When \
      you add a new server to your cluster, you can easily run the setup task \
      on just that server by specifying the HOSTS environment variable:

        $ cap HOSTS=new.server.com deploy:setup

      It is safe to run this task on servers that have already been set up; it \
      will not destroy any deployed revisions or data.
    DESC
    task :setup, :except => { :no_release => true } do
      dirs = [deploy_to, releases_path, shared_path]
      dirs += shared_children.map { |d| File.join(shared_path, d.split('/').last) }
      run "mkdir -p #{dirs.join(' ')}"
      run "chmod 755 #{dirs.join(' ')}" if fetch(:group_writable, true)
    end

    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      puts "STUB: Setup"
    end

    desc "Setup backup directory for database and web files"
    task :setup_backup, :except => { :no_release => true } do
      run "mkdir -p #{backups_path} #{tmp_backups_path} && chmod 755 #{backups_path}"
    end

    desc <<-DESC
      Deprecated API. This has become deploy:create_symlink, please update your recipes
    DESC
    task :symlink, :except => { :no_release => true } do
      logger.important "[Deprecation Warning] This API has changed, please hook `deploy:create_symlink` instead of `deploy:symlink`."
      create_symlink
    end

    desc <<-DESC
      Clean up old releases. By default, the last 5 releases are kept on each \
      server (though you can change this with the keep_releases variable). All \
      other deployed revisions are removed from the servers. By default, this \
      will use sudo to clean up the old releases, but if sudo is not available \
      for your environment, set the :use_sudo variable to false instead. \

      OVERRIDES:
      + set/reset file and directory permissions
      + remove old releases per host instead of assuming the releases are \
        the same for every host

      see http://blog.perplexedlabs.com/2010/09/08/improved-deploycleanup-for-capistrano/
    DESC
    task :cleanup, :except => { :no_release => true } do
      count = fetch(:keep_releases, 5).to_i
      cmd = "ls -xt #{releases_path}"
      run cmd do |channel, stream, data|
        local_releases = data.split.reverse
        if count >= local_releases.length
          logger.important "no old releases to clean up on #{channel[:server]}"
        else
          logger.info "keeping #{count} of #{local_releases.length} deployed releases on #{channel[:server]}"

          directories = (local_releases - local_releases.last(count)).map { |release|
            File.join(releases_path, release)
          }.join(" ")

          directories.split(" ").each do |dir|
            begin
              # adding a chown -R method to fix permissions on the directory
              # this should help with issues related to permission denied
              # as in issues #28 and #30
              run "chown -R #{user}:#{user} #{dir}" if remote_dir_exists?(dir)

              set_perms_dirs(dir)
              set_perms_files(dir)
            rescue Exception => e
              logger.important e.message
              logger.info "Moving on to the next directory..."
            end
          end

          run "#{try_sudo} rm -rf #{directories}", :hosts => [channel[:server]]
        end
      end
    end
  end

  # --------------------------------------------
  # Ash tasks
  # --------------------------------------------
  namespace :ash do
    desc "Set standard permissions for Ash servers"
    task :fixperms, :roles => :web, :except => { :no_release => true } do
      # chmod the files and directories.
      set_perms_dirs("#{latest_release}")
      set_perms_files("#{latest_release}")
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
      case true
      when remote_file_exists?("#{latest_release}/htaccess.#{stage}.dist")
        run "mv #{latest_release}/htaccess.#{stage}.dist #{latest_release}/.htaccess"
      when remote_file_exists?("#{latest_release}/htaccess.#{stage}")
        run "mv #{latest_release}/htaccess.#{stage} #{latest_release}/.htaccess"
      when remote_file_exists?("#{latest_release}/htaccess.dist")
        run "mv #{latest_release}/htaccess.dist #{latest_release}/.htaccess"
      else
        logger.important "Failed to move the .htaccess file in #{latest_release} because an unknown pattern was used"
      end
    end
  end

  # --------------------------------------------
  # SEO - robots.txt files
  # --------------------------------------------
  namespace :seo do
    desc <<-DESC
      Creates a robots.txt appropriate for the environment

      staging     => block all robots from indexing the site
      production  => allow robots to index the site
    DESC
    task :robots, :roles => :web do
      case "#{stage}"
      when 'staging'
        # block all robots from indexing anything
        robots_txt = <<-EOF
User-agent: *
Disallow: /
EOF
      when 'production'
        # allow all robots to index anything
        robots_txt = <<-EOF
User-agent: *
Disallow:
EOF
      else
        logger.important "SKIPPING creation of robots.txt because the #{stage} stage was unanticipated. You should override the `seo:robots` task with your own implementation."
      end

      # echo the file out into the root of the latest_release directory
      put robots_txt, "#{latest_release}/robots.txt"
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
  # NGINX tasks
  # --------------------------------------------
  namespace :nginx do
    %w(start stop restart reload status).each do |cmd|
      desc "[internal] - #{cmd.upcase} nginx and php-fpm"
      task cmd.to_sym, :roles => :web do

        nginx_cmd   = fetch(:nginx_init_command, "service nginx")
        phpfpm_cmd  = fetch(:phpfpm_init_command, "service php5-fpm")

        run "#{try_sudo} #{nginx_cmd} #{cmd}"
        run "#{try_sudo} #{phpfpm_cmd} #{cmd}"
      end
    end
  end


  # --------------------------------------------
  # Remote/Local database migration tasks
  # --------------------------------------------
  namespace :db do
    desc "Migrate remote application database to local server"
    task :to_local, :roles => :db, :except => { :no_release => true } do
      remote_export
      remote_download
      local_import
    end

    desc "Migrate local application database to remote server"
    task :to_remote, :roles => :db, :except => { :no_release => true } do
      local_export
      local_upload
      remote_import
    end

    desc "Handles importing a MySQL database dump file. Uncompresses the file, does regex replacements, and imports."
    task :local_import, :roles => :db do
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
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "--single-transaction --create-options --quick")

      system "#{mysqldump} #{dump_options} --opt -h#{db_local_host} -u#{db_local_user} -p#{db_local_pass} #{db_local_name} | gzip -c --best > #{db_local_name}.sql.gz"
    end

    desc "Upload locally created MySQL dumpfile to remote server via SCP"
    task :local_upload, :roles => :db do
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
      mysqldump     = fetch(:mysqldump, "mysqldump")
      dump_options  = fetch(:dump_options, "--single-transaction --create-options --quick")

      run "#{mysqldump} #{dump_options} --opt -h#{db_remote_host} -u#{db_remote_user} -p#{db_remote_pass} #{db_remote_name} | gzip -c --best > #{deploy_to}/#{db_remote_name}.sql.gz"
    end

    desc "Download remotely created MySQL dumpfile to local machine via SCP"
    task :remote_download, :roles => :db do
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
      deploy.setup_backup
      backup.db
      backup.web
      backup.cleanup
    end

    desc <<-DESC
      Requires the rsync package to be installed.

      Performs a file-level backup of the application and any assets \
      from the shared directory that have been symlinked into the \
      applications root or sub-directories.

      You can specify which files or directories to exclude from being \
      backed up (i.e., log files, sessions, cache) by setting the \
      :backup_exclude variable
          set(:backup_exclude) { [ "var/", "tmp/", "logs/debug.log" ] }
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
        logger.debug "Copying previous release to the #{tmp_backups_path}/#{release_name} directory"
        run "rsync -avzrtpL #{exclude_string} #{current_path}/ #{tmp_backups_path}/#{release_name}/"

        # --------------------------
        # SET/RESET PERMISSIONS
        # --------------------------
        begin
          set_perms_dirs("#{tmp_backups_path}/#{release_name}", 755)
          set_perms_files("#{tmp_backups_path}/#{release_name}", 644)

          # create the tarball of the previous release
          set :archive_name, "release_B4_#{release_name}.tar.gz"
          logger.debug "Creating a Tarball of the previous release in #{backups_path}/#{archive_name}"
          run "cd #{tmp_backups_path} && tar -cvpf - ./#{release_name}/ | gzip -c --best > #{backups_path}/#{archive_name}"

          # remove the the temporary copy
          logger.debug "Removing the temporary copy"
          run "rm -rf #{tmp_backups_path}/#{release_name}"
        rescue Exception => e
          logger.debug e.message
          logger.info "Error setting permissions on backed up files but continuing on..."
        end
      else
        logger.important "no previous release to backup; backup of files skipped"
      end
    end

    desc "Perform a backup of database files"
    task :db, :roles => :web do
      if previous_release
        mysqldump     = fetch(:mysqldump, "mysqldump")
        dump_options  = fetch(:dump_options, "--single-transaction --create-options --quick")
        dbhost        = fetch(:db_remote_host, 'localhost')

        puts "Backing up the database now and putting dump file in the previous release directory"

        # create the temporary copy for the release directory
        # which we'll tarball in the backup:web task
        run "mkdir -p #{tmp_backups_path}/#{release_name}"

        # define the filename (include the current_path so the dump file will be within the directory)
        filename = "#{tmp_backups_path}/#{release_name}/#{dbname}_dump-#{Time.now.to_s.gsub(/ /, "_")}.sql.gz"

        # ignored db tables
        ignore_tables     = fetch(:ignore_tables, [])
        ignore_tables_str = ''

        ignore_tables.each{ |t| ignore_tables_str << "--ignore-table='#{dbname}'.'" + t + "' " }

        # dump the database for the proper environment
        run "#{mysqldump} #{dump_options} -h #{dbhost} -u #{dbuser} -p #{dbname} #{ignore_tables_str} | gzip -c --best > #{filename}" do |ch, stream, out|
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

        begin
          archives = (backups - backups.last(count)).map { |backup|
            File.join(backups_path, backup) }.join(" ")

          # fix permissions on the the files and directories before removing them
          archives.split(" ").each do |backup|
            set_perms_dirs("#{backup}", 755) if remote_dir_exists?(backup)
            set_perms_files("#{backup}", 644) if remote_dir_exists?(backup)
          end

          run "rm -rf #{archives}"
        rescue Exception => e
          logger.important e.message
        end
      end
    end
  end

  # --------------------------------------------
  # Compass/Sass compiling
  # --------------------------------------------
  namespace :compass do
    desc "Compile SASS stylesheets and upload to remote server"
    task :default do
      # optional way to skip compiling of stylesheets and just upload them to the servers
      skip_compass_compile = fetch(:skip_compass_compile, false)

      compass.compile unless skip_compass_compile
      compass.upload_stylesheets
      ash.fixperms
    end

    desc 'Uploads compiled stylesheets to their matching watched directories'
    task :upload_stylesheets, :roles => :web, :except => { :no_release => true } do
      watched_dirs          = fetch(:compass_watched_dirs, nil)
      stylesheets_dir_name  = fetch(:stylesheets_dir_name, 'stylesheets')
      port                  = fetch(:port, 22)

      # finds all the web servers that we should upload stylesheets to
      servers = find_servers :roles => :web

      if !watched_dirs.nil?
        if watched_dirs.is_a? String
          logger.debug "Uploading compiled stylesheets for #{watched_dirs}"
          logger.debug "trying to upload stylesheets from ./#{watched_dirs}/#{stylesheets_dir_name} -> #{latest_release}/#{watched_dirs}/#{stylesheets_dir_name}"

          servers.each do |web_server|
            upload_command = "scp -r -P #{port} ./#{watched_dirs}/#{stylesheets_dir_name}/*.css #{user}@#{web_server}:#{latest_release}/#{watched_dirs}/#{stylesheets_dir_name}/"

            logger.info "running SCP command:"
            logger.debug upload_command
            system(upload_command)
          end
        elsif watched_dirs.is_a? Array
          logger.debug "Uploading compiled stylesheets for #{watched_dirs.join(', ')}"
          watched_dirs.each do |dir|
            logger.debug "trying to upload stylesheets from ./#{dir}/#{stylesheets_dir_name}/ -> #{latest_release}/#{dir}/#{stylesheets_dir_name}/"

            servers.each do |web_server|
              upload_command = "scp -r -P #{port} ./#{dir}/#{stylesheets_dir_name}/*.css #{user}@#{web_server}:#{latest_release}/#{dir}/#{stylesheets_dir_name}/"

              logger.info "running SCP command:"
              logger.debug upload_command
              system(upload_command)
            end
          end
        else
          logger.debug "Unable to upload compiled stylesheets because :compass_watched_dirs was neither a String nor an Array"
        end
      else
        logger.info "Skipping uploading of compiled stylesheets `compass:upload` because `:compass_watched_dirs` wasn't set"
      end
    end

    desc 'Compile minified version of CSS assets using Compass gem'
    task :compile, :roles => :web, :except => { :no_release => true } do
      watched_dirs          = fetch(:compass_watched_dirs, nil)
      skip_compass_compile  = fetch(:skip_compass_compile, false)


      if !watched_dirs.nil? && skip_compass_compile == false
        compass_bin_local     = find_compass_bin_path
        compass_bin           = fetch(:compass_bin, compass_bin_local)
        compass_env           = fetch(:compass_env, "production")
        compass_output        = fetch(:compass_output, 'compressed') # nested, expanded, compact, compressed

        if !compass_bin.nil?
          if watched_dirs.is_a? String
            logger.debug "Compiling SASS for #{watched_dirs}"
            system "#{compass_bin} clean ./#{watched_dirs} && #{compass_bin} compile --output-style #{compass_output} --environment #{compass_env} ./#{watched_dirs}"
          elsif watched_dirs.is_a? Array
            logger.debug "Compiling SASS for #{watched_dirs.join(', ')}"
            watched_dirs.each do |dir|
              system "#{compass_bin} clean ./#{dir} && #{compass_bin} compile --output-style #{compass_output} --environment #{compass_env} ./#{dir}"
            end
          else
            logger.debug "Unable to compile SASS because :compass_watched_dirs was neither a String nor an Array"
          end
        else
          logger.info "Skipping SASS compilation in `compass:compile` because unable to find the bin executable for the compass gem"
        end
      else
        logger.info "Skipping compass Sass compiliation"
      end
    end

    desc "Finds the bin executable path for the compass gem"
    task :find_compass_bin_path, :except => { :no_release => true } do
      begin
        spec      = Gem::Specification.find_by_name("compass")
        gem_root  = spec.gem_dir
        gem_bin   = gem_root + "/bin/compass"
      rescue Gem::LoadError => e
        logger.debug "Unable to find the gem 'compass'! Check to see if it's installed: `gem list -d compass` or install: `gem install compass`"
        gem_bin = nil
      rescue Exception => e
        logger.debug "Unable to find the compass executable bin path because of this error: #{e.message}"
        gem_bin = nil
      end

      logger.debug "Path to compass executable: #{gem_bin.inspect}"

      # return the path the compass executable
      gem_bin
    end
  end

  # --------------------------------------------
  # Track changes made to remote release file directory via a throw away git repo
  # --------------------------------------------
  namespace :watchdog do
    desc "Track changes made to remote release file directory via a throw away git repo"
    task :default, :roles => :web do
      watchdog.init_git_repo
      watchdog.init_git_ignore
      watchdog.commit
      watchdog.check_status
    end

    desc <<-DESC
      [internal] initialize a git repo in the latest release directory to track changes anybody makes to the filesystem
    DESC
    task :init_git_repo, :roles => :web do
      logger.important "Creating a local git repo in #{latest_release} to track changes done outside of our git-flow process"
      run "cd #{latest_release} && git init ." unless remote_dir_exists?("#{latest_release}/.git")
    end

    desc <<-DESC
      [internal] copy the .gitignore file from the cached-copy directory to only commit what we really care about
    DESC
    task :init_git_ignore, :roles => :web do
      logger.important "Copying the .gitignore file from the cached-copy directory"
      run "ln -s #{shared_path}/cached-copy/.gitignore #{latest_release}/.gitignore"
    end

    desc <<-DESC
      [internal] Adds and commits the files in the latest release directory
    DESC
    task :commit, :roles => :web do
      logger.important "Adding and committing the files in the latest release directory"
      run "cd #{latest_release} && git add . && git commit -m 'Keeping track of changes done outside of AAI git-flow'"
    end

    desc <<-DESC
      [internal] Adds and commits the files in the latest release directory
    DESC
    task :check_status, :roles => :web do
      logger.important "Checking status of git repo for any changes in watched files/directories"
      run "cd #{latest_release} && git status"
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
