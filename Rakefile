# frozen_string_literal: true

require "bundler/gem_tasks"
require "standard/rake"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rake/extensiontask"

task build: :compile

Rake::ExtensionTask.new("ob64_ext") do |ext|
  ext.ext_dir = "ext/ob64"
end

desc "Run benchmark"
task :benchmark do
  load "#{__dir__}/benchmark.rb"
end

task default: %i[clobber compile spec]
