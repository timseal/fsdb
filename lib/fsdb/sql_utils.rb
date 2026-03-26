# frozen_string_literal: true

module Fsdb
  module SqlUtils
    def self.like_escape(str)
      str.gsub("\\", "\\\\").gsub("%", "\\%").gsub("_", "\\_")
    end
  end
end
