# frozen_string_literal: true

require "sqlite3"
require "fileutils"

module Fsdb
  SCHEMA_SQL = <<~SQL
    CREATE TABLE IF NOT EXISTS entries (
      id           INTEGER PRIMARY KEY,
      path         TEXT    NOT NULL UNIQUE,
      name         TEXT    NOT NULL,
      is_dir       INTEGER NOT NULL,
      size_bytes   INTEGER,
      mtime        REAL,
      content_type TEXT,
      metadata     TEXT,
      scanned_at   REAL    NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_entries_path         ON entries(path);
    CREATE INDEX IF NOT EXISTS idx_entries_content_type ON entries(content_type);

    CREATE TABLE IF NOT EXISTS categories (
      id   INTEGER PRIMARY KEY,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE
    );

    CREATE TABLE IF NOT EXISTS entry_categories (
      entry_id     INTEGER NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
      category_id  INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      is_inherited INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (entry_id, category_id)
    );

    CREATE INDEX IF NOT EXISTS idx_ec_category ON entry_categories(category_id);
    CREATE INDEX IF NOT EXISTS idx_ec_entry    ON entry_categories(entry_id);
  SQL

  class DB
    DEFAULT_PATH = File.expand_path("~/.local/share/fsdb/fsdb.db")

    attr_reader :connection

    def self.open(path = nil, &block)
      instance = new(path || ENV.fetch("FSDB_DB", DEFAULT_PATH))
      if block
        begin
          block.call(instance)
        ensure
          instance.close
        end
      else
        instance
      end
    end

    def initialize(path)
      FileUtils.mkdir_p(File.dirname(path))
      @connection = SQLite3::Database.new(path)
      @connection.results_as_hash = true
      @connection.execute("PRAGMA foreign_keys = ON")
      @connection.execute("PRAGMA journal_mode = WAL")
      apply_migrations
    end

    def close
      @connection.close
    end

    def execute(sql, *params, &block)
      @connection.execute(sql, *params, &block)
    end

    def execute2(sql, *params, &block)
      @connection.execute2(sql, *params, &block)
    end

    def last_insert_row_id
      @connection.last_insert_row_id
    end

    def transaction(&block)
      @connection.transaction(&block)
    end

    private

    def apply_migrations
      # Execute each statement individually (SQLite3 gem doesn't support executescript well)
      SCHEMA_SQL.split(";").each do |stmt|
        stmt = stmt.strip
        @connection.execute(stmt) unless stmt.empty?
      end
    end
  end
end
