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

# Test to see if a file exists by providing 
# the full path to the expected file location
def remote_file_exists?(full_path)
  'true' ==  capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip
end