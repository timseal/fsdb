# frozen_string_literal: true

class BrowseController < ApplicationController
  def show
    @path    = File.expand_path(params[:path] || Dir.home)
    @entries = Fsdb::Query.list_under(db, @path, depth: 1)
  end

  private

  def db = @db ||= Fsdb::ArAdapter.new
end
