# frozen_string_literal: true

module Ob64
  # @abstract
  class Stream
    include Ob64::LibBase64

    private

    attr_reader :io, :decode_state, :encode_state

    public

    # Initializes the instance.
    #
    # @raise [NotImplementedError] if attempting to initialize an instance of +Ob64::Stream+
    def initialize(io)
      raise NotImplementedError, "abstract class" if instance_of?(Stream)

      @io = io
      @decode_state = Ob64::LibBase64::DecodeState.new
      @encode_state = Ob64::LibBase64::EncodeState.new
    end

    def close
      @io.close
    end

    def closed?
      @io.closed?
    end

    def eof
      @io.eof?
    end
    alias_method :eof?, :eof
  end
end
