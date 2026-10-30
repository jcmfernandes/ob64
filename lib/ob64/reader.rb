# frozen_string_literal: true

module Ob64
  # Reads the decoded version of the text in an io, like an IO: {#read},
  # {#readpartial}, {#eof?}, {#close}.
  #
  # Subclasses define +decode(text, eof)+, which decodes the pulled text not yet
  # decoded and returns <tt>[decoded, text_to_keep]</tt>; kept text is passed
  # again, with more text after it, on the next call. At +eof+ (no more text),
  # it decodes all or raises. It may call +stop+ to ignore the rest of the io.
  class Reader
    include Ext

    # Bytes of text pulled from the io at a time
    CHUNK = 65_536
    private_constant :CHUNK

    # @param io [IO] - responds to +readpartial+
    def initialize(io)
      @io = io
      @text = "".b
      @data = "".b
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
      if length&.positive? && @data.empty?
        outbuf&.clear
        return
      end
      output(take(length || @data.bytesize), outbuf)
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
        if @data.empty?
          outbuf&.clear
          raise EOFError, "end of file reached"
        end
      end
      output(take(maxlen), outbuf)
    end

    # Returns whether all the data was read. Pulls text from the io until some
    # data is decoded or the io ends.
    #
    # @return [Boolean]
    # @raise [ArgumentError] if the text cannot be decoded
    def eof?
      fill(1)
      @data.empty?
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

    # Bytes decoded so far: returned by +decode+, not kept text
    attr_reader :decoded

    # Ignores the rest of the io: the data ends with what +decode+ returns
    def stop
      @done = true
    end

    # Decodes until +length+ bytes are ready or the data ends
    def fill(length)
      until @data.bytesize >= length || @done
        chunk = pull
        @text << chunk if chunk
        bin, @text = decode(@text, chunk.nil?)
        @data << bin
        @decoded += bin.bytesize
        @done ||= chunk.nil?
      end
    end

    # Returns the next text from the io, binary, or nil at its end
    def pull
      chunk = @io.readpartial(CHUNK)
      @pulled += chunk.bytesize
      chunk.b
    rescue EOFError
      nil
    end

    def take(length)
      data = @data.byteslice(0, length)
      @data = @data.byteslice(data.bytesize..)
      data
    end

    def output(data, outbuf) = outbuf ? outbuf.replace(data) : data
  end
end
