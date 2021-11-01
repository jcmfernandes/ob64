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
