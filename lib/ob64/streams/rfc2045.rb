# frozen_string_literal: true

module Ob64
  module Base64
    module RFC2045
      # Writes the {RFC2045.encode} of the bytes written to it to an io.
      class Writer < Ob64::Writer
        # @param io [IO] - responds to +write+
        # @param line_length [Integer] - characters per line, a positive multiple of 4
        # @param crlf [Boolean] - if lines end with CRLF instead of LF
        # @raise [ArgumentError] if +line_length+ is not a positive multiple of 4
        def initialize(io, line_length = 60, crlf: false)
          __encode_rfc_2045("", line_length, crlf)
          super(io, line_length / 4 * 3)
          @line_length = line_length
          @crlf = crlf
        end

        private

        def encode(bin) = __encode_rfc_2045(bin, @line_length, @crlf)
      end

      # Reads the {RFC2045.decode} of the text in an io.
      class Reader < Ob64::Reader
        # Characters that decode; others are skipped, but '=' after 2 or 3 of a
        # group ends the data
        ALPHABET = "A-Za-z0-9+/"

        # A group start followed by '=' after 2 or 3 alphabet characters
        ENDS = /\A(?:[^#{ALPHABET}]*[#{ALPHABET}]){2}.*=/mo

        private

        # Decodes up to a whole number of groups of 4 alphabet characters; the
        # rest, at most 3 of them, waits for more text unless a '=' in it ends
        # the data. A piece decoding to fewer bytes than its groups hold had a
        # '=' ending the data.
        def decode(text, eof)
          return [__decode_rfc_2045(text), ""] if eof

          alpha = text.count(ALPHABET)
          cut = text.bytesize
          (alpha % 4).times { cut = text.byterindex(/[#{ALPHABET}]/o, cut - 1) }
          bin = __decode_rfc_2045(text.byteslice(0, cut))
          rest = text.byteslice(cut..)
          if bin.bytesize < alpha / 4 * 3
            stop
            [bin, ""]
          elsif ENDS.match?(rest)
            stop
            [bin + __decode_rfc_2045(rest), ""]
          else
            # Without a '=' ending the data, only its alphabet characters count
            [bin, rest.delete("^#{ALPHABET}")]
          end
        end
      end
    end
  end
end
