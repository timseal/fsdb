# frozen_string_literal: true

class Entry < ApplicationRecord
  has_many :entry_categories, dependent: :destroy
  has_many :categories, through: :entry_categories

  scope :dirs,  -> { where(is_dir: 1) }
  scope :files, -> { where(is_dir: 0) }
  scope :under, ->(path) {
    where("path LIKE ? ESCAPE '\\'", "#{Fsdb::SqlUtils.like_escape(path)}/%")
  }

  def dir? = is_dir == 1
  def file? = is_dir == 0
  def display_type = dir? ? "dir" : (content_type || "file")
end
