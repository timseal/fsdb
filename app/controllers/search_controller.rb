# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    @entries = if any_filters?
                 Fsdb::Query.search(
                   db,
                   category:     params[:category].presence,
                   content_type: params[:type].presence,
                   path_prefix:  params[:under].presence,
                   dirs_only:    params[:dirs] == "1",
                   limit:        (params[:limit] || 200).to_i,
                 )
               else
                 []
               end

    @categories    = Category.order(:name).pluck(:name)
    @content_types = Entry.where.not(content_type: nil).distinct.pluck(:content_type).sort
  end

  private

  def db = @db ||= Fsdb::ArAdapter.new

  def any_filters?
    params[:category].present? || params[:type].present? || params[:under].present?
  end
  helper_method :any_filters?
end
