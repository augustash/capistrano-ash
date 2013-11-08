# Require our base library.
require 'ash/base'
require 'railsless-deploy'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # --------------------------------------------
  # Setting nested WordPress variable defaults
  # --------------------------------------------

  # ------
  # Database Credentials
  # assumes you're using the same database user, password and database
  # as your main project would use; if you are not doing so, simply use
  # the following template for defining the credentials:
  #
  #    Alternative Database Credential Configuration:
  #      set :wp_db_user, "mycustomuser"
  #      set :wp_db_name, "custom_wp_database"
  #      set :wp_db_pass, proc{ Capistrano::CLI.password_prompt("Database password for '#{wp_db_user}':") }
  # ------
  set (:wp_db_user) { "#{dbuser}" }
  set (:wp_db_name) { "#{dbname}" }
  set (:wp_db_pass) { "#{dbpass}" }

  # ------
  # Multi-WordPress installations
  # Create an array of configuration settings for
  # each of the WordPress sites that should follow
  # the following defined for each installation:
  #
  #    :wp_blogs       # array, contains hashes with each hash
  #                    #   containing options for a given WordPress
  #                    #   installation
  #
  #    :directory      # string, relative file path to the WordPress
  #                    #   installation from the project's root directory
  #
  #    :db_prefix      # string, table prefix for all WordPress tables
  #
  #    :base_url       # hash, contains key/value pairs for environments and
  #                    #   their full URLs
  #                    #   NOTE: DO NOT INCLUDE the trailing slash "/" in the URL
  #
  # The following is an example of a well formed and
  # valid configuration array for multiple WordPress
  # installations
  #
  #    set :wp_blogs, [
  #       { :directory => "blog1", :db_prefix => "wp1_",
  #         :base_url => {
  #           :staging => "http://staging.example.com",
  #           :production => "http://www.example.com"
  #         }
  #       },
  #       { :directory => "blog2", :db_prefix => "wp2_",
  #         :base_url => {
  #           :staging => "http://staging.anotherexample.com",
  #           :production => "http://www.anotherexample.com"
  #         }
  #       }
  #     ]
  # ------
  set :wp_blogs, [ {} ]

  namespace :wordpress do
    namespace :nested do

      desc "Setup/configure nested wordpress installations"
      task :default, :roles => :web do
        wordpress.nested.setup      # setup shared directories for WP files (e.g., uploades, cache, etc.)
        wordpress.nested.symlink    # symlink configuration files and any shared directories
        wordpress.nested.protect    # protect the config file!
        wordpress.nested.updatedb   # update the WP database(s) with their home or base url
      end

      desc "Setup nested WordPress install"
      task :setup, :roles => :web do
        wordpress.nested.setup_shared
      end

      desc "Setup shared folders for WordPress"
      task :setup_shared, :roles => :web do
        wp_blogs.each do |blog|
          wp_blog_directory = blog[:directory]

          # create shared directories
          run "mkdir -p #{shared_path}/#{wp_blog_directory}/uploads"
          run "mkdir -p #{shared_path}/#{wp_blog_directory}/cache"
          # set correct permissions
          run "chmod -R 755 #{shared_path}/#{wp_blog_directory}"
        end
      end

      desc "[internal] Removes unnecessary files and directories"
      task :prepare_for_symlink, :roles => :web, :except => { :no_release => true } do
        wp_blogs.each do |blog|
          wp_blog_directory = blog[:directory]
          wp_uploads_path   = "#{wp_blog_directory}/wp-content/uploads"
          wp_cache_path     = "#{wp_blog_directory}/wp-content/cache"

          # remove shared directories
          run "rm -Rf #{latest_release}/#{wp_uploads_path}"
          run "rm -Rf #{latest_release}/#{wp_cache_path}"

          # Removing cruft files.
          run "rm -Rf #{latest_release}/#{wp_blog_directory}/license.txt"
          run "rm -Rf #{latest_release}/#{wp_blog_directory}/readme.html"
        end
      end

      desc "Links the correct settings file"
      task :symlink, :roles => :web, :except => { :no_release => true } do
        # internal call to the :prepare_for_symlink task
        wordpress.nested.prepare_for_symlink

        # symlink files/directories
        wp_blogs.each do |blog|
          wp_blog_directory = blog[:directory]
          wp_uploads_path   = "#{wp_blog_directory}/wp-content/uploads"
          wp_cache_path     = "#{wp_blog_directory}/wp-content/cache"

          run "ln -nfs #{shared_path}/#{wp_blog_directory}/uploads #{latest_release}/#{wp_uploads_path}"
          run "ln -nfs #{shared_path}/#{wp_blog_directory}/cache #{latest_release}/#{wp_cache_path}"
          run "ln -nfs #{latest_release}/#{wp_blog_directory}/wp-config.#{stage}.php #{latest_release}/#{wp_blog_directory}/wp-config.php"
        end
      end

      desc "Set WordPress Base URL in database"
      task :updatedb, :roles => :db, :except => { :no_release => true } do
        servers = find_servers_for_task(current_task)
        servers.each do |server|
          wp_db_host = server.host

          wp_blogs.each do |blog|
            wp_blog_directory   = blog[:directory]
            wp_db_prefix        = blog[:db_prefix]
            wp_base_url_prefix  = blog[:base_url]["#{stage}".to_sym]
            wp_base_url         = "#{wp_base_url_prefix}/#{wp_blog_directory}"

            run "mysql -h #{wp_db_host} -u #{wp_db_user} --password='#{wp_db_pass}' -e 'UPDATE #{wp_db_name}.#{wp_db_prefix}options SET option_value = \"#{wp_base_url}\" WHERE option_name = \"siteurl\" OR option_name = \"home\"'"
          end
        end
      end

      desc "Protect system files"
      task :protect, :except => { :no_release => true } do
        wp_blogs.each do |blog|
          wp_blog_directory = blog[:directory]
          run "chmod 444 #{latest_release}/#{wp_blog_directory}/wp-config.php*"
        end
      end
    end
  end

end
