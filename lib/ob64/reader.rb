# frozen_string_literal: true

require_relative "stream"

module Ob64
  # Decode base64-encoded streams.
  class Reader < Stream
    attr_reader :total_bytes_read

    def initialize(*)
      super

      @total_bytes_read = 0
    end

    # Decodes +length+ bytes from the I/O stream.
    #
    # +length+ must be a non-negative integer or +nil+.
    #
    # If +length+ is a positive integer, read tries to decode +length+ bytes
    # without any conversion (binary mode). It returns +nil+ if an EOF is
    # encountered before anything can be read. Fewer than +length+ bytes are
    # returned if an EOF is encountered during the read. In the case of an
    # integer length, the resulting string is always in ASCII-8BIT encoding.
    #
    # If +length+ is omitted or is +nil+, it reads until EOF and the encoding
    # conversion is applied, if applicable. A string is returned even if EOF is
    # encountered before any data is read.
    #
    # If +length+ is zero, it returns an empty string.
    #
    # If the optional +outbuf+ argument is present, it must reference a String,
    # which will receive the data. The +outbuf+ will contain only the received
    # data after the method call even if it is not empty at the beginning.
    #
    # When this method is called at end of file, it returns +nil+ or an emtpy
    # string, depending on length: +read+, +read(nil)+, and +read(0)+ return and
    # empty string, +read(positive_integer)+ returns +nil+.
    #
    # If a block is given, consecutive decoded chunks from the I/O stream are
    # yielded to the block and the number of bytes read is returned.
    #
    # @param length [Integer, nil]
    # @param outbuf [String, nil]
    # @return [String]
    # @yieldparam [String] chunk
    # @yieldreturn [Integer] the number of bytes read
    # @raise [ArgumentError] if +length+ is negative or isn't a multiple of 3
    # @raise [Ob64::DecodingError] if the I/O stream cannot be decoded
    def read(length = nil, outbuf: nil)
      raise ArgumentError, "negative length #{length} given" if length.to_i.negative?
      raise ArgumentError, "length must be multiple of 3" unless (length.to_i % 3).zero?

      return handle_read_at_eof(length) if eof?
      return String.new if length == 0

      encoded_length = length && Ob64.encoded_length_of(length, padding: false)
      if block_given?
        bytes_read = 0
        loop do
          decoded_data = __read(encoded_length, outbuf)
          bytes_read += decoded_data.length
          yield decoded_data

          break if eof?
        end
        bytes_read
      else
        __read(encoded_length, outbuf)
      end
    end

    private

    def handle_read_at_eof(length)
      case length
      when nil, 0
        String.new
      when 1..Float::INFINITY
        nil
      end
    end

    def __read(encoded_length, outbuf)
      decoded_data = __decode_stream(io.read(encoded_length), decode_state, outbuf)
      @total_bytes_read += decoded_data.length
      decoded_data
    end
  end
end
