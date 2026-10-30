# frozen_string_literal: true

module Ob64
  # Writes the encoded version of the bytes written to it to an io, like an IO:
  # {#write}, {#<<}, {#flush}, {#close}. {#finish} writes the end of the
  # encoding.
  #
  # The io is given the same String on every write, refilled each time: it must
  # not keep it.
  #
  # Subclasses pass +group+, the bytes that encode on their own (3, or a line's
  # worth), and define +encode(dst, src, off, len)+, which appends the encoding
  # of +src[off, len]+, whole groups or the tail at {#finish}, to +dst+.
  class Writer
    include Ext

    # @param io [IO] - responds to +write+; must not keep the String it is
    #   given, as it is reused
    # @param group [Integer] - bytes that encode on their own
    def initialize(io, group)
      @io = io
      @group = group
      # The bytes taken short of a group
      @bin = "".b
      # The encoding written to the io, refilled on every write
      @out = String.new(encoding: Encoding::US_ASCII)
      @finished = false
    end

    # Encodes +strings+ and writes the encoding of their whole groups to the io.
    # The rest waits for more bytes or {#finish}.
    #
    # @param strings [Array<String>]
    # @return [Integer] bytes taken: the sum of the bytesizes of +strings+ (converted
    #   with +to_s+)
    # @raise [IOError] after {#finish} or {#close}
    def write(*strings)
      check_open
      strings.map! { |string| String(string) }
      strings.sum { |string| take(string) }
    end

    # Like {#write}.
    #
    # @param string [String]
    # @return [Writer] self
    # @raise [IOError] after {#finish} or {#close}
    def <<(string)
      check_open
      take(String(string))
      self
    end

    # Flushes the io, if it responds to +flush+. Bytes short of a group still
    # wait.
    #
    # @return [Writer] self
    # @raise [IOError] after {#finish} or {#close}
    def flush
      check_open
      @io.flush if @io.respond_to?(:flush)
      self
    end

    # Writes the end of the encoding (the last bytes, padding, the last line) to
    # the io and keeps it open.
    #
    # @return [IO] the io
    # @raise [IOError] after {#finish} or {#close}
    def finish
      check_open
      encode(@out, @bin, 0, @bin.bytesize) unless @bin.empty?
      write_out
      @finished = true
      @io
    end

    # Like {#finish} unless already finished, then closes the io. Closing again
    # does nothing.
    #
    # @return [nil]
    def close
      finish unless @finished
      @io.close
      nil
    end

    private

    def check_open
      raise IOError, "closed stream" if @finished
    end

    # Encodes the whole groups of @bin and +string+, straight from +string+,
    # and writes them; keeps the rest in @bin. Returns the bytes taken.
    def take(string)
      size = string.bytesize
      off = 0
      unless @bin.empty?
        off = @group - @bin.bytesize
        off = size if size < off
        __append_into(@bin, string, 0, off)
        if @bin.bytesize == @group
          encode(@out, @bin, 0, @group)
          __consume(@bin, @group)
        end
      end
      whole = (size - off) / @group * @group
      encode(@out, string, off, whole) if whole > 0
      __append_into(@bin, string, off + whole, size - off - whole)
      write_out
      size
    end

    # Writes @out and empties it, keeping its buffer. If the io raises, @out
    # is written with the next write.
    def write_out
      return if @out.empty?

      @io.write(@out)
      __consume(@out, @out.bytesize)
    end
  end
end
