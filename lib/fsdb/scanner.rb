# frozen_string_literal: true

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
      @db             = db
      @root           = File.expand_path(root.to_s)
      @children_cache = {}
    end

    # Phase 1: walk filesystem, upsert all entries. Yields each dir path for progress display.
    # Each directory is read exactly once and cached for phase 2.
    # Returns {files: N, dirs: N}.
    def scan(&progress)
      files = dirs = 0
      queue = [@root]

      @db.transaction do
        until queue.empty?
          dir      = queue.shift
          children = safe_children(dir)
          @children_cache[dir] = children

          upsert_dir(dir)
          dirs += 1
          progress&.call(dir)

          children.each do |name|
            child = File.join(dir, name)
            next if File.symlink?(child)

            if File.directory?(child)
              queue << child
            elsif File.file?(child)
              upsert_file(child)
              files += 1
            end
          end
        end
      end

      { files:, dirs: }
    end

    # Returns [{path:, children:[]}] for every directory under root whose depth
    # is <= max_depth. Uses the cache populated during scan — no extra disk reads.
    def ai_candidate_dirs(max_depth: Integer(ENV.fetch("FSDB_AI_MAX_DEPTH", "3")))
      @children_cache.filter_map do |path, children|
        next if path == @root
        depth = path.delete_prefix("#{@root}/").count("/") + 1
        next unless depth <= max_depth

        { path:, children: }
      end.sort_by { |c| c[:path] }
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
