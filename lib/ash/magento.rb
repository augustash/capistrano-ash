# Required base libraries
require 'ash/base'
require 'railsless-deploy'

# Bootstrap Capistrano instance
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
  depend :remote, :command, 'rsync'

  # --------------------------------------------
  # try_sudo configuration
  # --------------------------------------------
  set :use_sudo, true                 # allow try_sudo methods to actually run via sudo
  # set(:admin_runner) {"#{user}"}    # specify the :admin_runner if you need to run it as another user other than root

  # Clear out the default prompt (i.e., `sudo -p 'sudo password: '`) to fall back
  # to just using `sudo` due to the concatenation in the sudo method.
  #
  # This assumes that you have set up your SSH user to have passwordless sudo
  # setup for common commands (e.g., chmod, rm, rsync, etc.)
  #
  # (see: https://github.com/capistrano/capistrano/blob/legacy-v2/lib/capistrano/configuration/actions/invocation.rb#L229-L237)
  set :sudo_prompt, ''

  # --------------------------------------------
  # Magento Variables
  # --------------------------------------------
  set :enable_modules, []
  set :disable_modules, %w(Ash_Bar)


  # --------------------------------------------
  # Database/Backup Variables
  # --------------------------------------------
  set :ignore_tables, %w(core_cache core_cache_option core_cache_tag core_session log_customer log_quote log_summary log_summary_type log_url log_url_info log_visitor log_visitor_info log_visitor_online enterprise_logging_event enterprise_logging_event_changes index_event index_process_event report_event report_viewed_product_index dataflow_batch_export dataflow_batch_import)

  # don't backup the media and var directories within the root
  # of Magento project (these are already in the shared directory)
  set :backup_exclude, %w(media var)

  # --------------------------------------------
  # Task chains
  # --------------------------------------------
  after "deploy:setup", "deploy:setup_local"
  after "deploy:finalize_update", "magento:activate_config"
  # after "deploy:create_symlink", "magento:symlink"

  # workaround for issues with capistrano v2.13.3 and
  # before/after callbacks not firing for 'deploy:symlink'
  # or 'deploy:create_symlink'
  after "deploy", "magento:symlink"
  after "magento:symlink", "magento:enable_mods"
  after "magento:enable_mods", "magento:disable_mods"
  after "magento:symlink", "magento:purge_cache"
  before "magento:purge_cache", "compass"

  # --------------------------------------------
  # Overloaded tasks
  # --------------------------------------------
  namespace :deploy do
    desc "Setup local files necessary for deployment"
    task :setup_local do
      # attempt to create files needed for proper deployment
      system("cp .htaccess htaccess.dist") unless local_file_exists?("htaccess.dist")
      stages = fetch(:stages, %w(staging production))
      stages.each do |env|
        system("cp app/etc/local.xml app/etc/local.xml.#{env}") unless local_file_exists?("app/etc/local.xml.#{env}")
      end
    end

    desc "Setup shared application directories and permissions after initial setup"
    task :setup_shared do
      # remove Capistrano specific directories
      try_sudo "rm -Rf #{shared_path}/log"
      try_sudo "rm -Rf #{shared_path}/pids"
      try_sudo "rm -Rf #{shared_path}/system"

      # create shared directories
      run "mkdir -p #{shared_path}/includes"
      run "mkdir -p #{shared_path}/media"
      run "mkdir -p #{shared_path}/sitemap"
      run "mkdir -p #{shared_path}/var"

      # set correct permissions
      set_perms("#{shared_path}/*", 777)
    end

    desc "[internal] Touches up the released code. This is called by update_code after the basic deploy finishes."
    task :finalize_update, :roles => :web, :except => { :no_release => true } do
      # synchronize media directory with shared data
      run "rsync -rltDvzog #{latest_release}/media/ #{shared_path}/media/"
      set_perms("#{shared_path}/media/", 777)

      # remove directories that will be shared
      run "rm -Rf #{latest_release}/includes"
      run "rm -Rf #{latest_release}/media"
      run "rm -Rf #{latest_release}/sitemap"
      run "rm -Rf #{latest_release}/var"

      # set the file and directory permissions
      ash.fixperms
      set_perms("#{latest_release}/pear", 400)
      set_perms("#{latest_release}/mage", 400)
      set_perms("#{latest_release}/app/etc", "o+w")
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

  namespace :compass do
    desc "Compile SASS stylesheets and upload to remote server"
    task :default do
      # optional way to skip compiling of stylesheets and just upload them to the servers
      skip_compass_compile = fetch(:skip_compass_compile, false)

      compass.compile unless skip_compass_compile
      compass.upload_stylesheets
      # fixperms for skin directory instead of the whole application (faster deploys)
      set_perms_dirs("#{latest_release}/skin")
      set_perms_files("#{latest_release}/skin")
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
      try_sudo "rm -Rf #{shared_path}/var/cache/*"
      try_sudo "rm -Rf #{shared_path}/var/full_page_cache/*" if remote_dir_exists?("#{shared_path}/var/full_page_cache}")
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

    desc "Clear the Magento Cache"
    task :cc, :roles => [:web, :app], :except => { :no_release => true } do
      run "chown -R #{user}:#{user} #{shared_path}/var/*"
      magento.purge_cache
    end

    desc "Enable display errors"
    task :enable_dev, :roles => :web, :except => { :no_release => true } do
      run "perl -pi -e 's/#ini_set/ini_set/g' #{latest_release}/index.php"
    end

    desc "Enable Modules"
    task :enable_mods, :roles => :web, :except => { :no_release => true } do
      modules = fetch(:enable_modules, [])
      # enable specific modules
      modules.each do |name|
        mod_name = name.include?('.xml') ? "#{name}" : "#{name}.xml"
        mod_path = "#{latest_release}/app/etc/modules/#{mod_name}"
        # enable the module
        run "perl -pi -e 's/false/true/g' #{mod_path}" if remote_file_exists?("#{mod_path}")
      end
    end

    desc "Disable Modules"
    task :disable_mods, :roles => :web, :except => { :no_release => true } do
      modules = fetch(:disable_modules, [])

      # enable specific modules
      modules.each do |name|
        mod_name = name.include?('.xml') ? "#{name}" : "#{name}.xml"
        mod_path = "#{latest_release}/app/etc/modules/#{mod_name}"
        # disable the module
        run "perl -pi -e 's/true/false/g' #{mod_path}" if remote_file_exists?("#{mod_path}")
      end
    end
  end

end
