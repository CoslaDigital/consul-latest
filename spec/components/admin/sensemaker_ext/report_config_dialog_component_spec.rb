# frozen_string_literal: true

require "rails_helper"

describe "Admin::Sensemaker::ReportConfigDialogComponent with SensemakerExt", type: :component do
  include_context "sensemaker report builder config schema"

  let(:debate) { create(:debate) }
  let(:sensemaker_job) do
    build(:sensemaker_job, analysable_type: "Debate", analysable_id: debate.id)
  end

  before do
    I18n.load_path += Dir[Rails.root.join("lib/sensemaker_ext/locales/*.yml")]
    I18n.load_path.uniq!
    I18n.reload!
    SensemakerExt::Loader.install!
  end

  it "renders excluded_opinions from the report-builder schema and submits report_ui" do
    render_inline(
      Admin::Sensemaker::ReportConfigDialogComponent.new(
        sensemaker_job,
        script: "report_ui"
      )
    )

    expect(page).to have_css("dialog#report-config-dialog-report-ui")
    expect(page).to have_field("sensemaker_job[run_options][config][excluded_opinions][]")
    expect(page).to have_content(I18n.t("admin.sensemaker.report_config.fields.excluded_opinions.label"))
    expect(page).to have_css("button[name='quick_action'][value='report_ui']")
  end
end
