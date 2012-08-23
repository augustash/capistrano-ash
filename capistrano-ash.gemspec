# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "capistrano-ash"
  s.version = "1.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["August Ash"]
  s.date = "2012-08-23"
  s.description = "August Ash recipes for Capistrano"
  s.email = "code@augustash.com"
  s.extra_rdoc_files = [
    "README.textile"
  ]
  s.files = [
    "CHANGELOG.rdoc",
    "README.textile",
    "Rakefile",
    "VERSION",
    "capistrano-ash.gemspec",
    "lib/ash/base.rb",
    "lib/ash/common.rb",
    "lib/ash/drupal.rb",
    "lib/ash/drupal_shared_hosting.rb",
    "lib/ash/hosted_magento.rb",
    "lib/ash/magento.rb",
    "lib/ash/wordpress.rb",
    "lib/ash/wordpress_shared_hosting.rb",
    "lib/ash/zend_doctrine.rb",
    "lib/ash/zend_doctrine_shared_hosting.rb"
  ]
  s.homepage = "https://github.com/augustash/capistrano-ash"
  s.require_paths = ["lib"]
  s.require "capistrano >= 2.11.2"
  s.rubygems_version = "1.8.21"
  s.summary = "Useful task libraries for August Ash recipes for Capistrano"

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end

