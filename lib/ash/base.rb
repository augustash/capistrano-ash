# set default stages
_cset :stages, %w(staging production)
_cset :default_stge, "staging"

# Required gems/libraries
require 'rubygems'
require 'railsless-deploy'
require 'capistrano/ext/multistage'
require 'ash/common'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)

configuration.load do

  # --------------------------------------------
  # Setting defaults
  # --------------------------------------------
  set :copy_exclude, [".svn", ".DS_Store", "*.sample", "LICENSE*", "Capfile", "config", "REVISION"]
  set :deploy_via, :remote_cache
  set :group_writable, false
  set :use_sudo, false
  set :scm, :subversion
  set :scm_verbose, true

  # show password requests on windows (http://weblog.jamisbuck.org/2007/10/14/capistrano-2-1)
  default_run_options[:pty] = true

  # --------------------------------------------
  # Ash methods
  # --------------------------------------------
  namespace :ash do
    desc "Fix the permissions on Ash servers"
    task :fixperms, :except => { :no_release => true } do
      # chmod the files and directories.
      run "find #{latest_release} -type d -exec chmod 755 {} \\;"
      run "find #{latest_release} -type f -exec chmod 644 {} \\;"
    end

    desc "Task for to test that Capistrano is working"
    task :uname do
      run "uname -a"
    end

    desc "Print environment of Capistrano user"
    task :getpath do
      run "echo $PATH"
    end
  end
end