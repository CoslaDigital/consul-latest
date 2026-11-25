# frozen_string_literal: true

require "rails_helper"

describe "Admin::Sensemaker::NewComponent with SensemakerExt", type: :component do
  include_context "sensemaker report ui config schema"
  include_context "sensemaker report builder config schema"

  let(:debate) { create(:debate) }
  let(:sensemaker_job) do
    Sensemaker::Job.new(analysable_type: "Debate", analysable_id: debate.id)
  end
  let(:component) { Admin::Sensemaker::NewComponent.new(sensemaker_job, [], 0) }

  before do
    I18n.load_path += Dir[Rails.root.join("lib/sensemaker_ext/locales/*.yml")]
    I18n.load_path.uniq!
    I18n.reload!
    SensemakerExt::Loader.install!
  end

  it "opens a prepare report dropdown of node and python scripts targeting schema dialogs" do
    allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
      .with(:summary).and_return(["runner.ts"])
    allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
      .with(:report).and_return(["sensemaking-report-ui", "report_ui"])
    allow(Sensemaker::ScriptRegistry).to receive(:backend_for).and_call_original
    allow(Sensemaker::ScriptRegistry).to receive(:i18n_key).and_call_original
    allow(Sensemaker::ScriptRegistry).to receive(:config_schema_path).and_call_original

    render_inline component

    toggle = ".quick-action-toggle[type='button'][aria-controls='sensemaker_report_scripts']"

    expect(page).to have_css toggle, text: I18n.t("admin.sensemaker.new.prepare_report")
    expect(page).to have_css(
      "#sensemaker_report_scripts button[type='button'][command='show-modal']" \
      "[commandfor='report-config-dialog-sensemaking-report-ui']"
    )
    expect(page).to have_css(
      "#sensemaker_report_scripts button[type='button'][command='show-modal']" \
      "[commandfor='report-config-dialog-report-ui']"
    )
    expect(page).to have_css("dialog#report-config-dialog-sensemaking-report-ui")
    expect(page).to have_css("dialog#report-config-dialog-report-ui")
    expect(page).to have_field("sensemaker_job[run_options][config][excluded_opinions][]")
  end
end
