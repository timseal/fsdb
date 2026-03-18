# frozen_string_literal: true

module Fsdb
  module Query
    ENTRY_SELECT = <<~SQL
      SELECT e.id, e.path, e.name, e.is_dir, e.size_bytes, e.mtime,
             e.content_type, e.metadata, e.scanned_at,
             GROUP_CONCAT(c.name, '|') AS category_names
      FROM entries e
      LEFT JOIN entry_categories ec ON ec.entry_id = e.id
      LEFT JOIN categories c ON c.id = ec.category_id
    SQL

    def self.search(db, category: nil, content_type: nil, path_prefix: nil, dirs_only: false, limit: 200)
      wheres  = []
      params  = []

      if category
        wheres << "e.id IN (SELECT ec2.entry_id FROM entry_categories ec2
                            JOIN categories c2 ON c2.id = ec2.category_id
                            WHERE c2.name = ? COLLATE NOCASE)"
        params << category
      end

      if content_type
        wheres << "e.content_type = ?"
        params << content_type
      end

      if path_prefix
        wheres << "e.path LIKE ?"
        params << "#{File.expand_path(path_prefix)}/%"
      end

      wheres << "e.is_dir = 1" if dirs_only

      where_sql = wheres.empty? ? "" : "WHERE #{wheres.join(" AND ")}"
      sql = "#{ENTRY_SELECT} #{where_sql} GROUP BY e.id ORDER BY e.path LIMIT ?"
      params << limit

      db.execute(sql, params).map { |row| row_to_entry(row) }
    end

    def self.list_under(db, path, depth: 1)
      path = File.expand_path(path.to_s)
      pattern = "#{path}/%"

      rows = db.execute(
        "#{ENTRY_SELECT} WHERE e.path LIKE ? GROUP BY e.id ORDER BY e.path",
        [pattern],
      ).map { |row| row_to_entry(row) }

      return rows unless depth

      rows.select do |entry|
        relative = entry.path.delete_prefix("#{path}/")
        relative.count("/") < depth
      end
    end

    def self.stats(db)
      total_entries = db.execute("SELECT COUNT(*) AS n FROM entries").first["n"]
      total_files   = db.execute("SELECT COUNT(*) AS n FROM entries WHERE is_dir = 0").first["n"]
      total_dirs    = db.execute("SELECT COUNT(*) AS n FROM entries WHERE is_dir = 1").first["n"]
      total_size    = db.execute("SELECT SUM(size_bytes) AS s FROM entries").first["s"] || 0

      by_type = db.execute(<<~SQL).map { |r| { type: r["content_type"] || "unrecognised", count: r["n"], size: r["s"] || 0 } }
        SELECT content_type, COUNT(*) AS n, SUM(size_bytes) AS s
        FROM entries WHERE is_dir = 0
        GROUP BY content_type ORDER BY n DESC
      SQL

      top_categories = db.execute(<<~SQL).map { |r| { name: r["name"], count: r["n"] } }
        SELECT c.name, COUNT(ec.entry_id) AS n
        FROM categories c
        JOIN entry_categories ec ON ec.category_id = c.id
        GROUP BY c.id ORDER BY n DESC LIMIT 15
      SQL

      uncategorised = db.execute(<<~SQL).first["n"]
        SELECT COUNT(*) AS n FROM entries e
        WHERE NOT EXISTS (
          SELECT 1 FROM entry_categories ec WHERE ec.entry_id = e.id
        )
      SQL

      {
        total_entries:,
        total_files:,
        total_dirs:,
        total_size:,
        by_type:,
        top_categories:,
        uncategorised:,
      }
    end

    private_class_method def self.row_to_entry(row)
      cats = row["category_names"]&.split("|")&.uniq || []
      Entry.new(
        id:           row["id"],
        path:         row["path"],
        name:         row["name"],
        is_dir:       row["is_dir"],
        size_bytes:   row["size_bytes"],
        mtime:        row["mtime"],
        content_type: row["content_type"],
        metadata:     row["metadata"],
        scanned_at:   row["scanned_at"],
        categories:   cats,
      )
    end
  end
end
