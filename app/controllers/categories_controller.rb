# frozen_string_literal: true

class CategoriesController < ApplicationController
  def index
    @categories = Category
      .left_joins(:entry_categories)
      .select("categories.*, COUNT(entry_categories.entry_id) AS entries_count")
      .group("categories.id")
      .order("entries_count DESC")
  end

  def show
    @category = Category.find(params[:id])
    @entries  = @category.entries.order(:path)
  end

  def update
    @category = Category.find(params[:id])
    if @category.update(name: params.require(:category).permit(:name)[:name])
      redirect_to categories_path, notice: "Category renamed."
    else
      redirect_to categories_path, alert: "Could not rename category."
    end
  end

  def destroy
    @category = Category.find(params[:id])
    @category.destroy
    redirect_to categories_path, notice: "Category removed."
  end
end
