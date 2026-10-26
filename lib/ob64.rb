# frozen_string_literal: true

require_relative "ob64/version"
require_relative "ob64_ext"

# Methods for base64- and uuencoding and -decoding strings.
module Ob64
  # The glue between Ruby and the C codecs. See +../ext/ob64/ob64_ext.c+.
  module Ext; end

  include Ext
  extend Ext

  module_function

  # Returns the Base64-encoded version of +bin+.
  # This method complies with RFC 4648.
  # No line feeds are added.
  #
  # @param bin [String]
  # @return [String]
  def encode(bin)
    __encode(bin, false, true)
  end

  # Returns the Base64-decoded version of +string+.
  # This method complies with RFC 4648.
  # ArgumentError is raised if +string+ is incorrectly padded or contains
  # non-alphabet characters. Note that CR or LF are also rejected.
  #
  # With +loose+, the padding character is optional: both correctly-padded
  # and unpadded input are accepted. Incorrectly-padded input is still
  # rejected.
  #
  # @param string [String]
  # @param loose [Boolean] - if unpadded input is accepted
  # @return [String]
  # @raise [ArgumentError] if +string+ cannot be decoded
  def decode(string, loose: false)
    __decode(string, false, loose)
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
    __encode(bin, true, padding)
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
    __decode(string, true, true)
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

  # Returns the uuencoded version of +bin+, like <tt>[bin].pack("u")</tt>:
  # lines of up to 45 input bytes, each ending in a newline.
  #
  # @param bin [String]
  # @return [String]
  def uuencode(bin)
    __uuencode(bin)
  end

  # Returns the uudecoded version of +string+, like <tt>string.unpack1("u")</tt>.
  # Decoding is lenient, as in Ruby: it stops at the first invalid line and
  # never raises for malformed input.
  #
  # @param string [String]
  # @return [String]
  def uudecode(string)
    __uudecode(string)
  end

  # Returns the smallest input size, in bytes, at which each SIMD codec is
  # used, or +nil+ if never. Lists only the codecs this CPU can run.
  # Below every size, plain C is used.
  #
  # The size is the input length when encoding, and +input_length * 3 / 4+
  # when decoding. The codec with the largest size <= the input's wins.
  # Applies to {encode}, {decode}, {urlsafe_encode} and {urlsafe_decode}.
  #
  # @return [Hash{Symbol => Integer, nil}] keys among +:avx2+, +:avx512+, +:neon64+
  def codec_routing
    __codec_routing
  end

  # Sets the smallest input size at which SIMD codecs are used.
  # See {codec_routing}.
  #
  # Codecs left out keep their size. Known codecs this CPU cannot run are
  # ignored, so the same routing works on every machine.
  #
  # @param routing [Hash{Symbol => Integer, nil}] keys among +:avx2+, +:avx512+, +:neon64+
  # @raise [TypeError] if +routing+ is not a Hash
  # @raise [ArgumentError] for an unknown codec, a size that is not +nil+ or
  #   a non-negative Integer, or two runnable codecs with the same size;
  #   the routing is then left unchanged
  def codec_routing=(routing)
    __set_codec_routing(routing)
  end
end
