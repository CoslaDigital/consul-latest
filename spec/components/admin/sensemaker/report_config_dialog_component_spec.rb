# frozen_string_literal: true

require "rails_helper"

describe Admin::Sensemaker::ReportConfigDialogComponent, type: :component do
  include_context "sensemaker report ui config schema"

  let(:debate) { create(:debate) }
  let(:sensemaker_job) do
    build(:sensemaker_job, analysable_type: "Debate", analysable_id: debate.id)
  end
  let(:default_title) { sensemaker_job.conversation.target_label(format: :full) }

  it "renders dialog fields with translated labels and submits the script" do
    render_inline(
      Admin::Sensemaker::ReportConfigDialogComponent.new(
        sensemaker_job,
        script: "sensemaking-report-ui"
      )
    )

    dialog_id = "report-config-dialog-sensemaking-report-ui"

    expect(page).to have_css("dialog##{dialog_id}")
    expect(page).to have_content(I18n.t("admin.sensemaker.new.report_config_hint"))
    expect(page).to have_field(
      "sensemaker_job_run_options_config_report-config-dialog-sensemaking-report-ui_title",
      with: default_title
    )
    expect(page).to have_field("sensemaker_job[run_options][config][logo]")
    expect(page).to have_field("sensemaker_job[run_options][config][excluded_topics][]")
    expect(page).not_to have_field("sensemaker_job[run_options][config][excluded_opinions][]")
    expect(page).to have_content(I18n.t("admin.sensemaker.report_config.fields.title.label"))
    expect(page).to have_button(I18n.t("admin.sensemaker.new.generate_report"))
    expect(page).to have_css("button[name='quick_action'][value='sensemaking-report-ui']")
  end
end
