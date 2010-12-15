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
  ui.ask(prompt) { |q| q.echo = true }
end