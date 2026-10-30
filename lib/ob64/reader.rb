# frozen_string_literal: true

module Ob64
  # Reads the decoded version of the text in an io, like an IO: {#read},
  # {#readpartial}, {#eof?}, {#close}.
  #
  # Subclasses define +decode(text, eof, dst)+, which decodes from the front of
  # +text+, the pulled text not yet decoded, appending the bytes to +dst+ and
  # removing the decoded text from +text+, in place. The text left is passed
  # again, with more text after it, on the next call. At +eof+ (no more text),
  # it decodes all or raises. It may call +stop+ to ignore the rest of the io.
  class Reader
    include Ext

    # Bytes of text pulled from the io at a time
    CHUNK = 65_536
    private_constant :CHUNK

    # @param io [IO] - responds to +readpartial(maxlen, outbuf)+
    def initialize(io)
      @io = io
      # The last text pulled
      @chunk = "".b
      # The text not yet decoded
      @text = "".b
      # The data decoded; bytes before @off are already read
      @data = "".b
      @off = 0
      @pulled = 0
      @decoded = 0
      @done = false
    end

    # Reads +length+ bytes, fewer only at the end, or all that is left without
    # +length+, like IO#read.
    #
    # @param length [Integer, nil]
    # @param outbuf [String, nil] - if given, its content is replaced by the data and it
    #   is returned
    # @return [String, nil] binary; +nil+ at the end if +length+ is positive
    # @raise [ArgumentError] if +length+ is negative or the text cannot be decoded
    def read(length = nil, outbuf = nil)
      raise ArgumentError, "negative length #{length} given" if length&.negative?

      fill(length || Float::INFINITY)
      if length&.positive? && available.zero?
        outbuf&.clear
        return
      end
      output(length || available, outbuf)
    end

    # Reads 1 to +maxlen+ bytes, as soon as any are decoded, like
    # IO#readpartial.
    #
    # @param maxlen [Integer]
    # @param outbuf [String, nil] - if given, its content is replaced by the data and it
    #   is returned
    # @return [String] binary
    # @raise [EOFError] at the end, if +maxlen+ is positive
    # @raise [ArgumentError] if +maxlen+ is negative or the text cannot be decoded
    def readpartial(maxlen, outbuf = nil)
      raise ArgumentError, "negative length #{maxlen} given" if maxlen.negative?

      if maxlen.positive?
        fill(1)
        if available.zero?
          outbuf&.clear
          raise EOFError, "end of file reached"
        end
      end
      output(maxlen, outbuf)
    end

    # Returns whether all the data was read. Pulls text from the io until some
    # data is decoded or the io ends.
    #
    # @return [Boolean]
    # @raise [ArgumentError] if the text cannot be decoded
    def eof?
      fill(1)
      available.zero?
    end
    alias_method :eof, :eof?

    # Closes the io.
    #
    # @return [nil]
    def close
      @io.close
      nil
    end

    private

    # Bytes of text pulled from the io so far
    attr_reader :pulled

    # Bytes decoded so far: appended by +decode+
    attr_reader :decoded

    # Ignores the rest of the io: the data ends with what +decode+ appends
    def stop
      @done = true
    end

    # Bytes decoded and not yet read
    def available = @data.bytesize - @off

    # Decodes until +length+ bytes are ready or the data ends
    def fill(length)
      until available >= length || @done
        eof = !pull
        # Drops the bytes read, keeping the buffer
        __consume(@data, @off) if @off > 0
        @off = 0
        size = @data.bytesize
        decode(@text, eof, @data)
        @decoded += @data.bytesize - size
        @done ||= eof
      end
    end

    # Appends the next text from the io to @text; false at its end
    def pull
      chunk = @io.readpartial(CHUNK, @chunk)
      @pulled += chunk.bytesize
      # A copy only if the io returned a String of its own
      @text << (chunk.equal?(@chunk) ? chunk.force_encoding(Encoding::BINARY) : chunk.b)
      true
    rescue EOFError
      false
    end

    # Returns the next +length+ bytes at most, in +outbuf+ if given
    def output(length, outbuf)
      n = available
      n = length if length < n
      if outbuf
        __copy_into(outbuf, @data, @off, n)
        outbuf.force_encoding(Encoding::BINARY)
      else
        outbuf = @data.byteslice(@off, n)
      end
      @off += n
      outbuf
    end
  end
end
