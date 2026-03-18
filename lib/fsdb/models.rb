# frozen_string_literal: true

module Fsdb
  Entry = Data.define(
    :id,
    :path,
    :name,
    :is_dir,
    :size_bytes,
    :mtime,
    :content_type,
    :metadata,
    :scanned_at,
    :categories,   # Array<String> — populated by JOIN queries
  ) do
    def dir? = is_dir == 1
    def file? = is_dir == 0

    def display_type
      return "dir" if dir?

      content_type || "other"
    end
  end

  Category = Data.define(:id, :name)
end
