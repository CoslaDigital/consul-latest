# spec/components/stv_detail_report_component_spec.rb

require "rails_helper"

RSpec.describe StvDetailReportComponent, type: :component do
  let(:rounds) do
    [
      {
        iteration: 1,
        quota: 5,
        standings: { 1 => 3.0, 2 => 2.5 },
        action: {
          type: :elimination,
          title: "Candidate B",
          candidate_id: 2,
          count: 2.5
        },
        transfers: {
          type: :elimination,
          candidate_id: 2,
          amount: 2.5,
          to: { 1 => 2.5 }
        },
        exhausted_total: 0.0
      },
      {
        iteration: 2,
        quota: 5,
        standings: { 1 => 5.5 },
        action: {
          type: :election,
          title: "Candidate A",
          candidate_id: 1,
          count: 5.5,
          surplus: 0.5,
          transfer_fraction: 0.09
        },
        transfers: {
          type: :surplus,
          candidate_id: 1,
          amount: 0.5,
          fraction: 0.09,
          to: {}
        },
        exhausted_total: 0.0
      }
    ]
  end

  let(:investment_titles) { { 1 => "Candidate A", 2 => "Candidate B" } }

  it "renders without raising" do
    render_inline(described_class.new(
      rounds: rounds,
      investment_titles: investment_titles
    ))

    expect(page).to have_text("Round 1")
    expect(page).to have_text("Round 2")
    expect(page).to have_text("Candidate A")
    expect(page).to have_text("Candidate B")
  end

  it "renders transfer destinations" do
    render_inline(described_class.new(
      rounds: rounds,
      investment_titles: investment_titles
    ))

    expect(page).to have_text("Transferred to:")
    expect(page).to have_text("+2.5")
  end

  it "renders the transfer fraction for surpluses" do
    render_inline(described_class.new(
      rounds: rounds,
      investment_titles: investment_titles
    ))

    expect(page).to have_text("Transfer value:")
    expect(page).to have_text("0.090000")
  end
end
