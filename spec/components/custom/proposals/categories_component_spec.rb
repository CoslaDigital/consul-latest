require "rails_helper"

describe Proposals::CategoriesComponent do
  before do
    # Clear out any existing tags to prevent cross-test pollution
    ActsAsTaggableOn::Tag.destroy_all
  end

  # Helper method to properly create a category and immediately bind it to a proposal
  # so that the Shared component's strict SQL JOIN recognizes it.
  def create_category_tag(name, proposal = nil)
    tag = create(:tag, name: name)
    tag.update_column(:kind, "category")

    if proposal
      ActsAsTaggableOn::Tagging.create!(tag: tag, taggable: proposal, context: "tags")
    end

    tag
  end

  describe "#render?" do
    it "does not render if there are no categories to show" do
      render_inline Proposals::CategoriesComponent.new(project: nil, search: nil)

      expect(page).not_to have_css(".categories")
    end

    it "renders if categories exist and are actually used by proposals" do
      proposal = create(:proposal)
      create_category_tag("Environment", proposal)
      create_category_tag("Health", proposal)

      render_inline Proposals::CategoriesComponent.new(project: nil, search: nil)

      expect(page).to have_link("Environment")
      expect(page).to have_link("Health")
    end
  end

  describe "dynamic filtering by project kind" do
    let!(:kind_a) { create(:proposal_kind, name: "Mutual Aid", slug: "mutual-aid") }
    let!(:kind_b) { create(:proposal_kind, name: "City Works", slug: "city-works") }

    before do
      proposal_a = create(:proposal, proposal_kind_id: kind_a.id)
      proposal_b = create(:proposal, proposal_kind_id: kind_b.id)

      create_category_tag("Environment", proposal_a)
      create_category_tag("Health", proposal_b)
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
      proposal = create(:proposal)
      create_category_tag("Environment", proposal)
    end

    it "highlights 'All Categories' when no search is active" do
      render_inline Proposals::CategoriesComponent.new(project: "mutual-aid", search: nil)

      expect(page).to have_css("a.is-active", text: "All Categories")
    end

    it "highlights the category and sets the URL to clear it when clicked" do
      render_inline Proposals::CategoriesComponent.new(project: "mutual-aid", search: "Environment")

      expect(page).to have_css("a.is-active", text: "Environment")

      link = page.find_link("Environment")
      expect(link[:href]).to include("project=mutual-aid")
      expect(link[:href]).not_to include("search=") # Confirms the parameter drops to toggle OFF
    end
  end
end
