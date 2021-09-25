# frozen_string_literal: true

require_relative "ob64/version"
require_relative "ob64_ext"

module Ob64
  include LibBase64
  extend LibBase64

  module_function

  def encode(bin)
    __encode(bin)
  end

  def decode(string)
    __decode(string)
  end

  def urlsafe_encode(bin, padding: true)
    string = __encode(bin)
    string.chomp!("==") || string.chomp!("=") unless padding
    string.tr!("+/", "-_")
    string
  end

  def urlsafe_decode(string)
    if !string.end_with?("=") && string.length % 4 != 0
      string = string.ljust((string.length + 3) & ~3, "=")
      string.tr!("-_", "+/")
    else
      string = string.tr("-_", "+/")
    end
    __decode(string)
  end

  def encoded_length_of(bin, padding: true)
    __encoded_length_of(bin, padding)
  end

  def decoded_length_of(string)
    __decoded_length_of(string)
  end
end
