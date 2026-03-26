# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    @stats = Fsdb::Query.stats(db)
  end

  private

  def db = @db ||= Fsdb::ArAdapter.new
end
