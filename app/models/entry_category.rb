# frozen_string_literal: true

class EntryCategory < ApplicationRecord
  self.primary_key = [:entry_id, :category_id]

  belongs_to :entry
  belongs_to :category
end
