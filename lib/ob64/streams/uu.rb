# frozen_string_literal: true

module Ob64
  module UU
    # Writes the {UU.encode} of the bytes written to it to an io.
    class Writer < Ob64::Writer
      # @param io [IO] - responds to +write+; must not keep the String it is
      #   given, as it is reused
      def initialize(io)
        super(io, 45)
      end

      private

      def encode(dst, src, off, len) = __uuencode_into(dst, src, off, len)
    end

    # Reads the {UU.decode} of the text in an io. Like +decode+, never raises
    # for malformed input.
    class Reader < Ob64::Reader
      private

      # Decodes whole lines. Like +decode+, the output is capped at 3/4 of the
      # text's length, and a cap reached may change how later lines parse: a
      # piece reaching the cap before eof waits for more text, its bytes
      # removed. Malformed lines that keep reaching it are decoded again on
      # each pull.
      def decode(text, eof, dst)
        cut = eof ? text.bytesize : (text.rindex("\n") || -1) + 1
        size = dst.bytesize
        cap = pulled * 3 / 4 - decoded
        stopped = __uudecode_capped_into(dst, text, cut, cap)
        if dst.bytesize - size == cap && !eof
          dst.slice!(size..)
          return
        end

        stop if stopped
        __consume(text, cut)
      end
    end
  end
end
