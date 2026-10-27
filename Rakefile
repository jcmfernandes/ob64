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

desc "Check the SIMD codecs against scalar in C, under ASan and UBSan; SEED=n repeats a run"
task "spec:c" do
  mkdir_p "tmp"
  sh "#{ENV.fetch("CC", "cc")} -std=gnu99 -O3 -g -fsanitize=address,undefined -fno-sanitize-recover=all " \
    "-fno-omit-frame-pointer -Wall -Wextra -Wno-unused-parameter -Werror -Iext/ob64 -o tmp/codecs_test " \
    "spec/c/codecs_test.c ext/ob64/pack_base64.c ext/ob64/pack_uuencode.c"
  # SDE: an emulator prefix, see .github/scripts/install-sde. It must run the test
  # itself: under SDE, ASan programs started by another one exit 0 unrun.
  sh "#{ENV["SDE"]} tmp/codecs_test #{ENV["SEED"]}"
end

desc "Run benchmark"
task :benchmark do
  load "#{__dir__}/benchmark.rb"
end

task default: %i[clobber compile spec]
