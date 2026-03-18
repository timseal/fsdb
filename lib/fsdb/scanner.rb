# frozen_string_literal: true

require "find"
require "fileutils"

module Fsdb
  class Scanner
    UPSERT_SQL = <<~SQL
      INSERT INTO entries (path, name, is_dir, size_bytes, mtime, content_type, scanned_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(path) DO UPDATE SET
        name         = excluded.name,
        is_dir       = excluded.is_dir,
        size_bytes   = excluded.size_bytes,
        mtime        = excluded.mtime,
        content_type = excluded.content_type,
        scanned_at   = excluded.scanned_at
    SQL

    def initialize(db, root, ai_suggest: false)
      @db         = db
      @root       = File.expand_path(root.to_s)
      @ai_suggest = ai_suggest
      @files      = 0
      @dirs       = 0
    end

    # Yields each directory path as it is processed (for progress display).
    def run(&progress)
      @db.transaction do
        Find.find(@root) do |path|
          next if File.symlink?(path)

          if File.directory?(path)
            upsert_dir(path)
            @dirs += 1
            progress&.call(path)
            maybe_suggest_ai(path) if @ai_suggest
          elsif File.file?(path)
            upsert_file(path)
            @files += 1
          end
        end
      end

      { files: @files, dirs: @dirs }
    end

    private

    def upsert_dir(path)
      stat = File.stat(path)
      @db.execute(UPSERT_SQL, [
        path,
        File.basename(path),
        1,
        nil,
        stat.mtime.to_f,
        nil,
        Time.now.to_f,
      ])
    end

    def upsert_file(path)
      stat = File.stat(path)
      content_type = ContentTypes.detect(path)
      @db.execute(UPSERT_SQL, [
        path,
        File.basename(path),
        0,
        stat.size,
        stat.mtime.to_f,
        content_type,
        Time.now.to_f,
      ])
    end

    def maybe_suggest_ai(dir_path)
      depth = dir_path.delete_prefix(@root).count("/")
      max_depth = Integer(ENV.fetch("FSDB_AI_MAX_DEPTH", "3"))
      return unless depth <= max_depth

      children = Dir.children(dir_path).first(60)
      existing = existing_categories

      suggestions = Ai.suggest_categories(dir_path, children, existing)
      suggestions.each do |cat|
        Tagger.assign(@db, dir_path, cat, propagate: false, is_inherited: false)
      end
    end

    def existing_categories
      @db.execute("SELECT name FROM categories ORDER BY name").map { |r| r["name"] }
    end
  end
end
