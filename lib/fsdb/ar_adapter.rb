# frozen_string_literal: true

module Fsdb
  # Duck-types the Fsdb::DB interface using ActiveRecord's connection pool.
  # Lets Query and Tagger modules work through AR without changes.
  class ArAdapter
    def execute(sql, params = [])
      raw_connection.execute(sql, params)
    end

    def last_insert_row_id
      raw_connection.last_insert_row_id
    end

    def transaction(&block)
      ActiveRecord::Base.transaction(&block)
    end

    private

    def raw_connection
      conn = ActiveRecord::Base.connection.raw_connection
      conn.results_as_hash = true unless conn.results_as_hash?
      conn
    end
  end
end
