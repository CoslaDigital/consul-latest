require "rails_helper"

describe Admin::Collaborations::IndexComponent, type: :component do
  # Use let! to force database creation BEFORE any tests or stubs run
  let!(:author) { create(:user, username: "MutualAidUser") }
  let!(:proposal) { create(:proposal, title: "Community Garden Project") }

  let!(:offer) do
    o = Offer.new(title: "Free Garden Tools")
    o.author = author
    o.save!(validate: false)
    o
  end

  let!(:match) do
    m = ProposalMatch.new(proposal: proposal, offer: offer, status: "pending")
    m.save!(validate: false)
    m
  end

  let(:matches) { ProposalMatch.where(id: match.id).page(1) }
  let(:offers) { Offer.where(id: offer.id).page(1) }

  subject(:render_component) { render_inline(described_class.new(matches: matches, offers: offers)) }

  context "when all records exist and are healthy" do
    it "renders the proposal, offer, author names, and correct match stages" do
      render_component

      # Verify basic text renders
      expect(page).to have_text("Community Garden Project")
      expect(page).to have_text("Free Garden Tools")
      expect(page).to have_text("MutualAidUser")

      # Verify our new Match Stage and Status columns render properly
      # Since the offer has an active match, it should say "Active" and "Pending"
      expect(page).to have_css(".label.success", text: "Active")
      expect(page).to have_css(".label.warning", text: "Pending")
    end
  end

  context "when an offer has no matches" do
    before do
      # Destroy the match to test the empty state
      match.destroy
    end

    it "renders the 'Unmatched' fallback stage" do
      render_component
      expect(page).to have_css(".label.secondary", text: "Unmatched")
    end
  end

  context "when a proposal is orphaned (hidden or soft-deleted)" do
    before do
      allow_any_instance_of(ProposalMatch).to receive(:proposal).and_return(nil)
    end

    it "renders the deleted proposal fallback text without crashing" do
      expect { render_component }.not_to raise_error
      expect(page).to have_text("[Deleted Proposal]")
    end
  end

  context "when an offer is orphaned (hidden or soft-deleted) on a match" do
    before do
      allow_any_instance_of(ProposalMatch).to receive(:offer).and_return(nil)
    end

    it "renders the deleted offer fallback text without crashing" do
      expect { render_component }.not_to raise_error
      expect(page).to have_text("[Deleted Offer]")
    end
  end

  context "when an offer's author is deleted" do
    before do
      allow_any_instance_of(Offer).to receive(:author).and_return(nil)
    end

    it "renders the deleted user fallback text without crashing" do
      expect { render_component }.not_to raise_error
      expect(page).to have_text("[Deleted User]")
    end
  end
end
