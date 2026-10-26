# frozen_string_literal: true

require "ob64"

::Array.prepend(Ob64::Ext::Pack)
::String.prepend(Ob64::Ext::Unpack)
