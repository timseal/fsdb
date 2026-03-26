# frozen_string_literal: true

Rails.application.config.after_initialize do
  db_path = ENV.fetch("FSDB_DB", File.expand_path("~/.local/share/fsdb/fsdb.db"))

  unless File.exist?(db_path)
    Rails.logger.warn "[fsdb] Database not found at #{db_path}. Run 'fsdb scan <path>' to create it."
  end

  ActiveRecord::Base.connection.execute("PRAGMA foreign_keys = ON")
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode = WAL")
end
