# frozen_string_literal: true

module Ob64
  module Base64
    module RFC2045
      # Writes the {RFC2045.encode} of the bytes written to it to an io.
      class Writer < Ob64::Writer
        # @param io [IO] - responds to +write+; must not keep the String it is
        #   given, as it is reused
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

        def encode(dst, src, off, len) = __encode_rfc_2045_into(dst, src, off, len, @line_length, @crlf)
      end

      # Reads the {RFC2045.decode} of the text in an io.
      class Reader < Ob64::Reader
        # Characters that decode; others are skipped, but '=' after 2 or 3 of a
        # group ends the data
        ALPHABET = "A-Za-z0-9+/"

        # Characters skipped
        SKIPPED = "^#{ALPHABET}"

        # Whether each byte is in ALPHABET
        ALPHABETIC = Array.new(256) { |b| b.chr.count(ALPHABET) == 1 }.freeze

        # A group start followed by '=' after 2 or 3 alphabet characters
        ENDS = /\A(?:[^#{ALPHABET}]*[#{ALPHABET}]){2}.*=/mo
        private_constant :ALPHABET, :SKIPPED, :ALPHABETIC, :ENDS

        private

        # Decodes up to a whole number of groups of 4 alphabet characters; the
        # rest, at most 3 of them, waits for more text unless a '=' in it ends
        # the data. A piece decoding to fewer bytes than its groups hold had a
        # '=' ending the data.
        def decode(text, eof, dst)
          cut = text.bytesize
          unless eof
            alpha = text.count(ALPHABET)
            (alpha % 4).times do
              cut -= 1
              cut -= 1 until ALPHABETIC[text.getbyte(cut)]
            end
          end
          n = __decode_rfc_2045_into(dst, text, cut)
          __consume(text, cut)
          return if eof

          if n < alpha / 4 * 3
            stop
          elsif ENDS.match?(text)
            stop
            __decode_rfc_2045_into(dst, text, text.bytesize)
          else
            # Without a '=' ending the data, only its alphabet characters count
            text.delete!(SKIPPED)
          end
        end
      end
    end
  end
end
