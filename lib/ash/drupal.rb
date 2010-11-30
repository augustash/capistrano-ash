# Require our base library.
require 'capistrano/ash/base'

configuration = Capistrano::Configuration.respond_to?(:instance) ?
  Capistrano::Configuration.instance(:must_exist) :
  Capistrano.configuration(:must_exist)
  
configuration.load do

# --------------------------------------------
# Setting defaults
# --------------------------------------------
_cset :multisites, {"default" => "default"}

# --------------------------------------------
# Calling our Methods
# --------------------------------------------
after "deploy:finalize_update", "drupal:setup"
after "deploy:symlink", "drupal:symlink"
after "deploy", "drupal:clearcache"
after "deploy", "deploy:cleanup"
        
# --------------------------------------------
# Overloaded Methods
# --------------------------------------------
namespace :deploy do
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
                run "/usr/local/bin/drush -l #{url} -r #{latest_release} vset --yes site_offline 1"
            end
        end

        desc "Enable the application and remove the message screen"
        task :enable do
            multisites.each_pair do |folder, url|
                run "/usr/local/bin/drush -l #{url} -r #{latest_release} vdel --yes site_offline"
            end
        end
    end
end

# --------------------------------------------
# Drupal-specific methods
# --------------------------------------------
namespace :drupal do
   desc "Setup shared Drupal directories and permissions"
   task :setup, :except => { :no_release => true } do
        multisites.each_pair do |folder, url|
            run "mkdir -p #{shared_path}/#{url}/files"
        end
        sudo "chmod -R 777 #{shared_path}/*"
   end
   
   desc "Symlink shared directories"
   task :symlink, :except => { :no_release => true } do
        multisites.each_pair do |folder, url|
            run "ln -nfs #{shared_path}/#{url}/files #{current_release}/sites/#{url}/files"
            run "ln -nfs #{latest_release}/sites/#{url}/settings.php.#{stage} #{latest_release}/sites/#{url}/settings.php"
            run "/usr/local/bin/drush -l #{url} -r #{current_path} vset --yes file_directory_path sites/#{url}/files"
        end
   end
   
   desc "Replace local database paths with remote paths"
   task :updatedb, :except => { :no_release => true } do
       multisites.each_pair do |folder, url|
           run "/usr/local/bin/drush -l #{url} -r #{current_path} sqlq \"UPDATE {files} SET filepath = REPLACE(filepath,'sites/#{folder}/files','sites/#{url}/files');\""
       end
   end
   
    desc "Clear all Drupal cache"
    task :clearcache, :except => { :no_release => true } do
        multisites.each_pair do |folder, url|
            run "/usr/local/bin/drush -l #{url} -r #{current_path} cache-clear all"
        end
    end
end
    
end