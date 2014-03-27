require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name        = "capistrano-ash"
    gemspec.summary     = "Useful task libraries for August Ash recipes for Capistrano"
    gemspec.description = "August Ash recipes for Capistrano"
    gemspec.email       = "code@augustash.com"
    gemspec.homepage    = "https://github.com/augustash/capistrano-ash"
    gemspec.authors     = ["August Ash"]
    # Gem dependencies
    gemspec.add_dependency('capistrano', '~> 2.15.5')
    gemspec.add_dependency('capistrano-ext')
    gemspec.add_dependency('railsless-deploy')
    gemspec.add_dependency('capistrano_colors')

    # Net-SSH issues
    # see https://github.com/capistrano/capistrano/issues/927
    gemspac.add_dependency('net-ssh', '2.7.0')

  end
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end
