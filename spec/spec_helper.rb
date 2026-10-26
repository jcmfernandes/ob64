# frozen_string_literal: true

# Captured before ob64/core_ext patches them, for differential specs.
NATIVE_PACK = Array.instance_method(:pack)
NATIVE_UNPACK = String.instance_method(:unpack)
NATIVE_UNPACK1 = String.instance_method(:unpack1)

require "ob64"

require "debug"

RSpec.configure do |config|
  config.order = "random"

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
end
