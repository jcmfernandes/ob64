# frozen_string_literal: true

require_relative "ob64/version"
require_relative "ob64_ext"

# Fast base64 and uuencode encoding and decoding: see {Base64} and {UU}.
module Ob64
  # The glue between Ruby and the C codecs. See +../ext/ob64/ob64_ext.c+.
  module Ext; end

  include Ext
  extend Ext

  module_function

  # Returns the codec used by {Base64}, {UU} and, with +ob64/core_ext+,
  # +pack+ and +unpack+ with +m+ and +u+. Defaults to {best_codec}.
  #
  # @return [Symbol] one of {codecs}
  def codec
    __codec
  end

  # Forces a codec for the whole process: every thread and Ractor.
  #
  # @param codec [Symbol] one of {codecs}
  # @return [Symbol] +codec+
  # @raise [ArgumentError] if +codec+ is unknown or this CPU cannot run it
  def codec=(codec)
    __set_codec(codec)
  end

  # Returns the codecs this CPU runs, best last. +:scalar+ is plain C.
  #
  # @return [Array<Symbol>] among +:scalar+, +:avx2+, +:avx512+, +:neon64+
  def codecs
    __codecs
  end

  # Returns the best codec this CPU runs, the default {codec}.
  #
  # @return [Symbol] one of {codecs}
  def best_codec
    codecs.last
  end

  # Methods for base64-encoding and -decoding strings.
  module Base64
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
  end

  # Methods for uuencoding and -decoding strings.
  module UU
    include Ext
    extend Ext

    module_function

    # Returns the uuencoded version of +bin+, like <tt>[bin].pack("u")</tt>:
    # lines of up to 45 input bytes, each ending in a newline.
    #
    # @param bin [String]
    # @return [String]
    def encode(bin)
      __uuencode(bin)
    end

    # Returns the uudecoded version of +string+, like <tt>string.unpack1("u")</tt>.
    # Decoding is lenient, as in Ruby: it stops at the first invalid line and
    # never raises for malformed input.
    #
    # @param string [String]
    # @return [String]
    def decode(string)
      __uudecode(string)
    end

    # Returns the length of the uuencoded version of +bin+.
    #
    # @param bin [String]
    # @return [Integer]
    def encoded_length_of(bin)
      __uuencoded_length_of(bin)
    end

    # Returns the length of the uudecoded version of +string+.
    # Like {decode}, never raises for malformed input.
    #
    # @param string [String]
    # @return [Integer]
    def decoded_length_of(string)
      __uudecoded_length_of(string)
    end
  end
end
