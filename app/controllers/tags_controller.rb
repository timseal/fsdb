# frozen_string_literal: true

class TagsController < ApplicationController
  def create
    entry = Entry.find(params[:entry_id])
    category_name = params[:category_name].to_s.strip

    if category_name.present?
      Fsdb::Tagger.assign(db, entry.path, category_name)
      entry.reload
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(entry, :tags), partial: "shared/tag_badges", locals: { entry: entry }) }
      format.html { redirect_back fallback_location: browse_path }
    end
  rescue Fsdb::Tagger::NotCatalogued => e
    redirect_back fallback_location: browse_path, alert: e.message
  end

  def destroy
    entry    = Entry.find(params[:entry_id])
    category = Category.find(params[:id])

    Fsdb::Tagger.remove(db, entry.path, category.name)
    entry.reload

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(entry, :tags), partial: "shared/tag_badges", locals: { entry: entry }) }
      format.html { redirect_back fallback_location: browse_path }
    end
  rescue Fsdb::Tagger::NotCatalogued => e
    redirect_back fallback_location: browse_path, alert: e.message
  end

  private

  def db = @db ||= Fsdb::ArAdapter.new
end
