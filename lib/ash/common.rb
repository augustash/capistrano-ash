# Accepts a parameter name and value and registers it as a default within Capistrano.
# Params:
# +name+
# +args+
# +block+
def _cset(name, *args, &block)
  unless exists?(name)
    set(name, *args, &block)
  end
end

# Prompts user entry
# Params:
# +prompt+
def text_prompt(prompt="Value: ")
  Capistrano::CLI.ui.ask(prompt) { |q| q.echo = true }
end

# Check if a file exists by providing the full path to the expected file location
def local_file_exists?(full_path)
  File.exists?(full_path)
end

# Check if a directory exists by providing the full path to the expected location
def local_dir_exists?(full_path)
  File.directory?(full_path)
end

# Test to see if a file exists by providing
# the full path to the expected file location
def remote_file_exists?(full_path)
  'true' ==  capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
end

# Test to see if a directory exists on a remote
# server by providing the full path to the expected
# directory
#
# Params:
#   +dir_path+
def remote_dir_exists?(dir_path)
  'true' == capture("if [[ -d #{dir_path} ]]; then echo 'true'; fi").strip
end

# set the permissions for files recurisvely from the starting directory (dir_path)
def set_perms_files(dir_path, perm = 644)
  begin
    run "find #{dir_path} -type f -print0 | xargs -0 -L 500 #{try_sudo} chmod #{perm}" if remote_dir_exists?(dir_path)
  rescue Exception => e
    logger.important "FAILED to set permissions of #{perm} on files within #{dir_path}!"
    logger.important e.message
    logger.important "Trying to set permissions without using xargs"
    begin
      run "find #{dir_path} -type f -exec #{try_sudo} chmod #{perm} {} \\;"  if remote_dir_exists?(dir_path)
    rescue Exception => e
      logger.important "FAILED second attempt to set permissions of #{perm} on files within #{dir_path}!"
      logger.important e.message
    end
  end
end

# set the permissions for directories recursively from the starting directory (dir_path)
def set_perms_dirs(dir_path, perm = 755)
  begin
    run "find #{dir_path} -type d -print0 | xargs -0 -L 500 #{try_sudo} chmod #{perm}" if remote_dir_exists?(dir_path)
  rescue Exception => e
    logger.important "FAILED to set permissions of #{perm} on directories within #{dir_path}!"
    logger.important e.message
    logger.important "Trying to set permissions without using xargs"
    begin
      run "find #{dir_path} -type d -exec #{try_sudo} chmod #{perm} {} \\;"  if remote_dir_exists?(dir_path)
    rescue Exception => e
      logger.important "FAILED second attempt to set permissions of #{perm} on directories within #{dir_path}!"
      logger.important e.message
    end
  end
end

# set permission on specific file or directory path instead of doing
# it with a big hammer like set_perms_files or set_perms_dir
def set_perms(path, perm = 644)
  begin
    try_sudo "chmod #{perm} #{path}" if remote_file_exists?(path) || remote_dir_exists?(path)
  rescue Exception => e
    logger.important "FAILED to set permission of #{perm} on #{path}"
    logger.important e.message
  end
end
