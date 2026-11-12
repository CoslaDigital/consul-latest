require "rails_helper"

describe Proposals::KindsComponent do
  describe "#render?" do
    it "does not render if there are 0 project types" do
      ProposalKind.destroy_all

      render_inline Proposals::KindsComponent.new(project: nil, search: nil)

      expect(page).not_to have_css(".sidebar-title")
    end

    it "does not render if there is only 1 project type" do
      ProposalKind.destroy_all
      create(:proposal_kind, name: "Default")

      render_inline Proposals::KindsComponent.new(project: nil, search: nil)

      expect(page).not_to have_css(".sidebar-title")
    end

    it "renders if there are 2 or more project types" do
      ProposalKind.destroy_all
      create(:proposal_kind, name: "Type A")
      create(:proposal_kind, name: "Type B")

      render_inline Proposals::KindsComponent.new(project: nil, search: nil)

      expect(page).to have_css("h2.sidebar-title", text: "Project Types")
      expect(page).to have_link("Type A")
      expect(page).to have_link("Type B")
    end
  end

  describe "active states and link clearing" do
    before do
      ProposalKind.destroy_all
      @type_a = create(:proposal_kind, name: "Type A", slug: "type-a")
      @type_b = create(:proposal_kind, name: "Type B", slug: "type-b")
    end

    it "highlights 'All Types' and clears search when clicked" do
      render_inline Proposals::KindsComponent.new(project: nil, search: "parks")

      expect(page).to have_css("a.is-active", text: "All Types")

      link = page.find_link("All Types")
      expect(link[:href]).not_to include("project=")
      expect(link[:href]).not_to include("search=") # Confirms search is wiped
    end

    it "highlights the specific project type and clears search when clicked" do
      render_inline Proposals::KindsComponent.new(project: "type-b", search: "parks")

      expect(page).to have_css("a.is-active", text: "Type B")

      link = page.find_link("Type B")
      expect(link[:href]).to include("project=type-b")
      expect(link[:href]).not_to include("search=") # Confirms search is wiped
    end
  end
end
