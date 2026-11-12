class Shared::CategoriesComponent < ApplicationComponent
  attr_reader :taggable_type, :taggable_ids, :current_search, :url_method, :url_params

  def initialize(taggable_type:, current_search:, url_method:, url_params: {}, taggable_ids: nil)
    @taggable_type = taggable_type
    @taggable_ids = taggable_ids
    @current_search = current_search
    @url_method = url_method
    @url_params = url_params.compact # Cleans out any nil parameters
  end

  def render?
    categories.any?
  end

  def categories
    @categories ||= begin
                      scope = ActsAsTaggableOn::Tag.where(kind: "category").order(:name)
                      scope = scope.joins(:taggings).where(taggings: { taggable_type: taggable_type })

                      # If specific IDs are provided (e.g. a specific budget), restrict the tags to only those
                      if taggable_ids.present?
                        scope = scope.where(taggings: { taggable_id: taggable_ids })
                      end

                      scope.distinct
                    end
  end

  def active?(category)
    current_search == category.name
  end

  def category_url(category_name)
    # Automatically generates paths like `proposals_path(project: "X", search: "Y")`
    # or `budget_investments_path(budget_id: 1, search: "Y")`
    helpers.send(url_method, url_params.merge(search: category_name))
  end
end
