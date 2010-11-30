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
_cset :copy_exclude, [".svn", ".DS_Store", "*.sample", "LICENSE*", "Capfile", "config"]
_cset :deploy_via, :remote_cache
_cset :group_writable, false
_cset :use_sudo, false

# --------------------------------------------
# Calling our Methods
# --------------------------------------------
after "deploy:finalize_update", "ash:fixperms"

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