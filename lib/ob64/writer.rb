# frozen_string_literal: true

module Ob64
  # Writes the encoded version of the bytes written to it to an io, like an IO:
  # {#write}, {#<<}, {#flush}, {#close}. {#finish} writes the end of the
  # encoding.
  #
  # Subclasses pass +group+, the bytes that encode on their own (3, or a line's
  # worth), and define +encode(bin)+, which encodes whole groups, or the tail at
  # {#finish}.
  class Writer
    include Ext

    # @param io [IO] - responds to +write+
    # @param group [Integer] - bytes that encode on their own
    def initialize(io, group)
      @io = io
      @group = group
      @bin = "".b
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
      strings = strings.map { |string| String.new(string.to_s, encoding: Encoding::BINARY) }
      strings.each { |string| @bin << string }
      whole = @bin.bytesize / @group * @group
      emit(@bin.byteslice(0, whole))
      @bin = @bin.byteslice(whole..)
      strings.sum(&:bytesize)
    end

    # Like {#write}.
    #
    # @param string [String]
    # @return [Writer] self
    # @raise [IOError] after {#finish} or {#close}
    def <<(string)
      write(string)
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
      emit(@bin)
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

    def emit(bin)
      @io.write(encode(bin)) unless bin.empty?
    end
  end
end
