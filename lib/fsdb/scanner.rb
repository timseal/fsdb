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

    def initialize(db, root)
      @db   = db
      @root = File.expand_path(root.to_s)
    end

    # Phase 1: walk filesystem, upsert all entries. Yields each dir path for progress display.
    # Returns {files: N, dirs: N}.
    def scan(&progress)
      files = dirs = 0

      @db.transaction do
        Find.find(@root) do |path|
          next if File.symlink?(path)

          if File.directory?(path)
            upsert_dir(path)
            dirs += 1
            progress&.call(path)
          elsif File.file?(path)
            upsert_file(path)
            files += 1
          end
        end
      end

      { files:, dirs: }
    end

    # Returns [{path:, children:[]}] for every catalogued directory under root
    # whose depth (relative to root) is <= max_depth. Called after scan.
    def ai_candidate_dirs(max_depth: Integer(ENV.fetch("FSDB_AI_MAX_DEPTH", "3")))
      rows = @db.execute(
        "SELECT path FROM entries WHERE is_dir = 1 AND path LIKE ? ORDER BY path",
        ["#{@root}/%"],
      )

      rows.filter_map do |row|
        path  = row["path"]
        depth = path.delete_prefix("#{@root}/").count("/") + 1
        next unless depth <= max_depth

        children = safe_children(path)
        { path:, children: }
      end
    end

    # Phase 2: run AI suggestions in batches. Yields (batch_index, total_batches) for progress.
    # Returns total number of categories assigned.
    def suggest_in_batches(candidates, batch_size:, &on_batch)
      return 0 if candidates.empty?

      existing    = existing_categories
      batches     = candidates.each_slice(batch_size).to_a
      total       = batches.size
      assigned    = 0

      batches.each_with_index do |batch, i|
        on_batch&.call(i + 1, total)

        suggestions = Ai.suggest_categories_batch(batch, existing)
        suggestions.each do |path, cats|
          cats.each do |cat|
            Tagger.assign(@db, path, cat, propagate: false, is_inherited: false)
            existing |= [cat]
            assigned += 1
          end
        end
      end

      assigned
    end

    private

    def upsert_dir(path)
      stat = File.stat(path)
      @db.execute(UPSERT_SQL, [path, File.basename(path), 1, nil, stat.mtime.to_f, nil, Time.now.to_f])
    end

    def upsert_file(path)
      stat         = File.stat(path)
      content_type = ContentTypes.detect(path)
      @db.execute(UPSERT_SQL, [path, File.basename(path), 0, stat.size, stat.mtime.to_f, content_type, Time.now.to_f])
    end

    def existing_categories
      @db.execute("SELECT name FROM categories ORDER BY name").map { |r| r["name"] }
    end

    def safe_children(path)
      Dir.children(path)
    rescue Errno::EACCES, Errno::ENOENT
      []
    end
  end
end
