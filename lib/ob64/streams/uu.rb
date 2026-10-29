# frozen_string_literal: true

module Ob64
  module UU
    # Writes the {UU.encode} of the bytes written to it to an io.
    class Writer < Ob64::Writer
      # @param io [IO] - responds to +write+
      def initialize(io)
        super(io, 45)
      end

      private

      def encode(bin) = __uuencode(bin)
    end

    # Reads the {UU.decode} of the text in an io. Like +decode+, never raises
    # for malformed input.
    class Reader < Ob64::Reader
      private

      # Decodes whole lines. Like +decode+, the output is capped at 3/4 of the
      # text's length, and a cap reached may change how later lines parse: a
      # piece reaching the cap before eof waits for more text. Malformed lines
      # that keep reaching it are decoded again on each pull.
      def decode(text, eof)
        cut = eof ? text.bytesize : (text.rindex("\n") || -1) + 1
        piece = text.byteslice(0, cut)
        cap = pulled * 3 / 4 - decoded
        bin, stopped = __uudecode_capped(piece, cap)
        return ["".b, text] if bin.bytesize == cap && !eof

        stop if stopped
        [bin, text.byteslice(cut..)]
      end
    end
  end
end
