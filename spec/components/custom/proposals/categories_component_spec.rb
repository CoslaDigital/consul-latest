require "rails_helper"

describe Proposals::CategoriesComponent do
  before do
    # Clear out any existing tags to prevent cross-test pollution
    ActsAsTaggableOn::Tag.destroy_all
  end

  describe "#render?" do
    it "does not render if there are no categories to show" do
      render_inline Proposals::CategoriesComponent.new(project: nil, search: nil)

      expect(page).not_to have_css(".categories")
    end

    it "renders if categories exist" do
      # 1. Create tags and FORCE the kind column to "category" bypassing protections
      env_tag = create(:tag, name: "Environment")
      env_tag.update_column(:kind, "category")

      health_tag = create(:tag, name: "Health")
      health_tag.update_column(:kind, "category")

      render_inline Proposals::CategoriesComponent.new(project: nil, search: nil)

      expect(page).to have_link("Environment")
      expect(page).to have_link("Health")
    end
  end

  describe "dynamic filtering by project kind" do
    let!(:kind_a) { create(:proposal_kind, name: "Mutual Aid", slug: "mutual-aid") }
    let!(:kind_b) { create(:proposal_kind, name: "City Works", slug: "city-works") }

    before do
      # 1. Create tags and FORCE the kind column to "category"
      tag_a = create(:tag, name: "Environment")
      tag_a.update_column(:kind, "category")

      tag_b = create(:tag, name: "Health")
      tag_b.update_column(:kind, "category")

      # 2. Create the proposals and explicitly link them via Taggings
      # using Consul's native "tags" context.
      proposal_a = create(:proposal, proposal_kind_id: kind_a.id)
      ActsAsTaggableOn::Tagging.create!(tag: tag_a, taggable: proposal_a, context: "tags")

      proposal_b = create(:proposal, proposal_kind_id: kind_b.id)
      ActsAsTaggableOn::Tagging.create!(tag: tag_b, taggable: proposal_b, context: "tags")
    end

    it "shows all categories when no project is selected" do
      render_inline Proposals::CategoriesComponent.new(project: nil, search: nil)

      expect(page).to have_link("Environment")
      expect(page).to have_link("Health")
    end

    it "only shows categories used by proposals within the selected project type" do
      render_inline Proposals::CategoriesComponent.new(project: "mutual-aid", search: nil)

      expect(page).to have_link("Environment")
      expect(page).not_to have_link("Health")
    end
  end

  describe "active states and toggling" do
    before do
      tag = create(:tag, name: "Environment")
      tag.update_column(:kind, "category")
    end

    it "highlights 'All Categories' when no search is active" do
      render_inline Proposals::CategoriesComponent.new(project: "mutual-aid", search: nil)

      expect(page).to have_css("a.is-active", text: "All Categories")
    end

    it "highlights the category and sets the URL to clear it when clicked" do
      render_inline Proposals::CategoriesComponent.new(project: "mutual-aid", search: "Environment")

      expect(page).to have_css("a.is-active", text: "Environment")

      # Grab the rendered link and verify its parameter structure directly
      link = page.find_link("Environment")
      expect(link[:href]).to include("project=mutual-aid")
      expect(link[:href]).not_to include("search=") # Confirms the search param is dropped to toggle it off
    end
  end
end
