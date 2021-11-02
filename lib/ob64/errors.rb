# frozen_string_literal: true

module Ob64
  class Error < StandardError; end

  class UnsupportedCodecError < Error; end

  class DecodingError < Error; end
end
