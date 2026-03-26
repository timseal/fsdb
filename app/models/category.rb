# frozen_string_literal: true

class Category < ApplicationRecord
  has_many :entry_categories, dependent: :destroy
  has_many :entries, through: :entry_categories
end
