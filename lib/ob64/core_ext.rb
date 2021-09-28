# frozen_string_literal: true

require "ob64"
require "base64"

module Ob64
  module CoreExt
    def strict_encode64(bin)
      Ob64.strictier_encode(bin)
    end

    def strict_decode64(str)
      Ob64.strictier_decode(str)
    end

    def urlsafe_encode64(bin, padding: true)
      Ob64.urlsafe_encode(bin, padding: padding)
    end

    def urlsafe_decode64(str)
      Ob64.urlsafe_decode(str)
    end
  end

  ::Base64.prepend(CoreExt)
  ::Base64.singleton_class.prepend(CoreExt)

  private_constant :CoreExt
end
