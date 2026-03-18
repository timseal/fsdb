# frozen_string_literal: true

module Fsdb
  module Tagger
    class NotCatalogued < StandardError; end

    def self.assign(db, path, category_name, propagate: false, is_inherited: false)
      path = normalize(path)
      entry_id = find_entry_id!(db, path)
      cat_id   = get_or_create_category(db, category_name)

      upsert_entry_category(db, entry_id, cat_id, is_inherited)

      return unless propagate

      descendant_ids(db, path).each do |desc_id|
        upsert_entry_category(db, desc_id, cat_id, true)
      end
    end

    def self.remove(db, path, category_name, propagate: false)
      path   = normalize(path)
      cat_id = db.execute("SELECT id FROM categories WHERE name = ? COLLATE NOCASE", [category_name])
                 .first&.dig("id")
      return unless cat_id

      entry_id = find_entry_id!(db, path)
      db.execute("DELETE FROM entry_categories WHERE entry_id = ? AND category_id = ?", [entry_id, cat_id])

      return unless propagate

      descendant_ids(db, path).each do |desc_id|
        db.execute("DELETE FROM entry_categories WHERE entry_id = ? AND category_id = ?", [desc_id, cat_id])
      end
    end

    def self.normalize(path)
      File.expand_path(path.to_s)
    end

    private_class_method def self.find_entry_id!(db, path)
      row = db.execute("SELECT id FROM entries WHERE path = ?", [path]).first
      raise NotCatalogued, "#{path} is not in the catalogue — run 'fsdb scan #{path}' first" unless row

      row["id"]
    end

    private_class_method def self.get_or_create_category(db, name)
      name = name.downcase.strip
      row  = db.execute("SELECT id FROM categories WHERE name = ? COLLATE NOCASE", [name]).first
      return row["id"] if row

      db.execute("INSERT INTO categories (name) VALUES (?)", [name])
      db.last_insert_row_id
    end

    private_class_method def self.upsert_entry_category(db, entry_id, cat_id, is_inherited)
      db.execute(
        "INSERT OR REPLACE INTO entry_categories (entry_id, category_id, is_inherited) VALUES (?, ?, ?)",
        [entry_id, cat_id, is_inherited ? 1 : 0],
      )
    end

    private_class_method def self.descendant_ids(db, path)
      pattern = "#{path}/%"
      db.execute("SELECT id FROM entries WHERE path LIKE ?", [pattern]).map { |r| r["id"] }
    end
  end
end
