# frozen_string_literal: true

module Ob64
  module Base64
    module RFC4648
      # Writes the {RFC4648.encode} (or, with +urlsafe+,
      # {RFC4648.encode_urlsafe}) of the bytes written to it to an io.
      class Writer < Ob64::Writer
        # @param io [IO] - responds to +write+
        # @param urlsafe [Boolean] - if the ``URL and Filename Safe'' alphabet is used
        # @param padding [Boolean] - if the output must be padded
        def initialize(io, urlsafe: false, padding: true)
          super(io, 3)
          @urlsafe = urlsafe
          @padding = padding
        end

        private

        def encode(bin) = __encode(bin, @urlsafe, @padding)
      end

      # Reads the {RFC4648.decode} (or, with +urlsafe+,
      # {RFC4648.decode_urlsafe}) of the text in an io. ArgumentError is raised
      # where +decode+ raises, possibly after returning the bytes before the bad
      # spot.
      class Reader < Ob64::Reader
        # @param io [IO] - responds to +readpartial(maxlen, outbuf)+
        # @param urlsafe [Boolean] - if the ``URL and Filename Safe'' alphabet is used;
        #   padding is then optional
        # @param loose [Boolean] - if unpadded input is accepted
        def initialize(io, urlsafe: false, loose: false)
          super(io)
          @urlsafe = urlsafe
          @loose = loose || urlsafe
          @padded = false
        end

        private

        # Decodes groups of 4 strictly and, at eof, the rest as configured.
        # After '=', more text is invalid.
        def decode(text, eof, dst)
          raise ArgumentError, "invalid base64" if @padded && !text.empty?

          cut = eof ? text.bytesize : text.bytesize / 4 * 4
          pad = text.byteindex("=")
          @padded = true if pad && pad < cut
          __decode_into(dst, text, cut, @urlsafe, eof && @loose)
          __consume(text, cut)
        end
      end
    end
  end
end
