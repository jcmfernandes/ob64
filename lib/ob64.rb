# frozen_string_literal: true

require_relative "ob64/version"
require_relative "ob64_ext"

# Methods for base64-encoding and -decoding strings.
module Ob64
  # The glue between Ruby and libbase64. See +../ext/libbase64/ob64/ob64_ext.c+.
  module LibBase64; end

  include LibBase64
  extend LibBase64

  module_function

  # Returns the Base64-encoded version of +bin+.
  # This method complies with RFC 4648.
  # No line feeds are added.
  #
  # @param bin [String]
  # @return [String]
  def encode(bin)
    __encode(bin)
  end

  # Returns the Base64-decoded version of +string+.
  # This method complies with RFC 4648.
  # ArgumentError is raised if +string+ is incorrectly padded or contains
  # non-alphabet characters. Note that CR or LF are also rejected.
  #
  # @param string [String]
  # @return [String]
  # @raise [ArgumentError] if +string+ cannot be decoded
  def decode(string)
    __decode(string)
  end

  # Returns the Base64-encoded version of +bin+.
  # This method complies with ``Base 64 Encoding with URL and Filename Safe
  # Alphabet'' in RFC 4648.
  # The alphabet uses '-' instead of '+' and '_' instead of '/'.
  # Note that the result can still contain '='.
  # You can remove the padding by setting +padding+ as false.
  #
  # @param bin [String]
  # @param padding [Boolean] - if the output must be padded
  # @return [String]
  def urlsafe_encode(bin, padding: true)
    string = __encode(bin)
    string.chomp!("==") || string.chomp!("=") unless padding
    string.tr!("+/", "-_")
    string
  end

  # Returns the Base64-decoded version of +string+.
  # This method complies with ``Base 64 Encoding with URL and Filename Safe
  # Alphabet'' in RFC 4648.
  # The alphabet uses '-' instead of '+' and '_' instead of '/'.
  #
  # The padding character is optional.
  # This method accepts both correctly-padded and unpadded input.
  # Note that it still rejects incorrectly-padded input.
  #
  # @param string [String]
  # @return [String]
  # @raise [ArgumentError] if +string+ cannot be decoded
  def urlsafe_decode(string)
    if !string.end_with?("=") && string.length % 4 != 0
      string = string.ljust((string.length + 3) & ~3, "=")
      string.tr!("-_", "+/")
    else
      string = string.tr("-_", "+/")
    end
    __decode(string)
  end

  # Returns the length of the Base64-encoded version of +bin+.
  #
  # @param bin [String]
  # @param padding [Boolean] - if the Base64-encoded version of +bin+ will be padded
  # @return [Integer]
  def encoded_length_of(bin, padding: true)
    __encoded_length_of(bin, padding)
  end

  # Returns the length of the Base64-decoded version of +string+.
  #
  # ArgumentError is raised if +string+ has an invalid length.
  #
  # @param string [String]
  # @return [Integer]
  # @raise [ArgumentError] if +string+ has an invalid length
  def decoded_length_of(string)
    __decoded_length_of(string)
  end
end
