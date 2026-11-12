require "rails_helper"

describe Shared::CategoriesComponent do
  before do
    # Clear out any existing tags to prevent cross-test pollution
    ActsAsTaggableOn::Tag.destroy_all
  end

  # Helper method to properly create a category and bind it to a taggable record
  def create_category_tag(name, taggable)
    tag = create(:tag, name: name)
    tag.update_column(:kind, "category")
    ActsAsTaggableOn::Tagging.create!(tag: tag, taggable: taggable, context: "tags")
    tag
  end

  describe "#render?" do
    it "does not render if there are no categories to show" do
      render_inline Shared::CategoriesComponent.new(
        taggable_type: "Proposal",
        current_search: nil,
        url_method: :proposals_path
      )

      expect(page).not_to have_css(".categories")
    end

    it "renders if categories exist for the given taggable_type" do
      proposal = create(:proposal)
      create_category_tag("Environment", proposal)

      render_inline Shared::CategoriesComponent.new(
        taggable_type: "Proposal",
        current_search: nil,
        url_method: :proposals_path
      )

      expect(page).to have_link("Environment")
    end
  end

  describe "strict scoping by type and IDs" do
    it "only shows categories attached to the specified taggable_type" do
      proposal = create(:proposal)
      debate = create(:debate) # Core Consul factory

      create_category_tag("Proposal Tag", proposal)
      create_category_tag("Debate Tag", debate)

      render_inline Shared::CategoriesComponent.new(
        taggable_type: "Proposal",
        current_search: nil,
        url_method: :proposals_path
      )

      expect(page).to have_link("Proposal Tag")
      expect(page).not_to have_link("Debate Tag") # Ignored because it belongs to a Debate
    end

    it "filters strictly by taggable_ids when they are provided" do
      proposal_1 = create(:proposal)
      proposal_2 = create(:proposal)

      create_category_tag("Included", proposal_1)
      create_category_tag("Excluded", proposal_2)

      # Simulate a filtered subquery (e.g. proposals in a specific project)
      filtered_ids = Proposal.where(id: proposal_1.id).select(:id)

      render_inline Shared::CategoriesComponent.new(
        taggable_type: "Proposal",
        taggable_ids: filtered_ids,
        current_search: nil,
        url_method: :proposals_path
      )

      expect(page).to have_link("Included")
      expect(page).not_to have_link("Excluded")
    end
  end

  describe "URL generation and active states" do
    before do
      proposal = create(:proposal)
      create_category_tag("Health", proposal)
    end

    it "highlights 'All Categories' and builds search links for inactive categories" do
      render_inline Shared::CategoriesComponent.new(
        taggable_type: "Proposal",
        current_search: nil,
        url_method: :proposals_path,
        url_params: { project: "mutual-aid" }
      )

      expect(page).to have_css("a.is-active", text: "All Categories")

      # Verifies the inactive category builds a link that TURNS ON the search
      health_link = page.find_link("Health")
      expect(health_link[:href]).to include("project=mutual-aid")
      expect(health_link[:href]).to include("search=Health")
    end

    it "highlights the active category and builds a clearing link to toggle it off" do
      render_inline Shared::CategoriesComponent.new(
        taggable_type: "Proposal",
        current_search: "Health",
        url_method: :proposals_path,
        url_params: { project: "mutual-aid" }
      )

      expect(page).to have_css("a.is-active", text: "Health")

      # Verifies the active category builds a link that TURNS OFF the search
      health_link = page.find_link("Health")
      expect(health_link[:href]).to include("project=mutual-aid")
      expect(health_link[:href]).not_to include("search=")
    end
  end
end
