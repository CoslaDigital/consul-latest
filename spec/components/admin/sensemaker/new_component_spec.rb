require "rails_helper"

describe Admin::Sensemaker::NewComponent do
  include_context "sensemaker report ui config schema"

  let(:sensemaker_job) { Sensemaker::Job.new }
  let(:component) { Admin::Sensemaker::NewComponent.new(sensemaker_job, [], 0) }

  describe "#quick_action_label" do
    it "returns the localized label for each quick action" do
      expect(component.quick_action_label(:summary))
        .to eq(I18n.t("admin.sensemaker.new.generate_summary"))
    end
  end

  describe "#quick_prep_label" do
    it "returns the localized prepare label" do
      expect(component.quick_prep_label(:report))
        .to eq(I18n.t("admin.sensemaker.new.prepare_report"))
    end
  end

  describe "#quick_action_scripts" do
    it "returns every script registered for the logical name" do
      expect(component.quick_action_scripts(:summary)).to include("runner.ts")
      expect(component.quick_action_scripts(:report)).to include("sensemaking-report-ui")
    end

    it "lists the preferred backend script first" do
      allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
        .with(:summary).and_return(["other-summary", "runner.ts"])
      allow(Sensemaker::ScriptRegistry).to receive(:backend_for).and_call_original
      allow(Sensemaker::ScriptRegistry).to receive(:backend_for).with("other-summary").and_return(:other)

      expect(component.quick_action_scripts(:summary)).to eq(["runner.ts", "other-summary"])
    end

    it "keeps the registry order when no preferred backend script is registered" do
      allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
        .with(:summary).and_return(["other-summary"])
      allow(Sensemaker::ScriptRegistry).to receive(:backend_for).with("other-summary").and_return(:other)

      expect(component.quick_action_scripts(:summary)).to eq(["other-summary"])
    end
  end

  describe "quick action buttons" do
    let(:debate) { create(:debate) }
    let(:sensemaker_job) do
      Sensemaker::Job.new(analysable_type: "Debate", analysable_id: debate.id)
    end

    context "when a quick action has a single script" do
      before do
        allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
          .with(:summary).and_return(["runner.ts"])
        allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
          .with(:report).and_return(["sensemaking-report-ui"])
      end

      it "submits summary directly and opens prepare report dialog for report" do
        render_inline component

        expect(page).to have_button I18n.t("admin.sensemaker.new.generate_summary")
        expect(page).to have_css "button[name='quick_action'][value='runner.ts']"
        expect(page).to have_button I18n.t("admin.sensemaker.new.prepare_report")
        expect(page).to have_css(
          "button[type='button'][command='show-modal'][commandfor='report-config-dialog-sensemaking-report-ui']"
        )
        expect(page).to have_css("dialog#report-config-dialog-sensemaking-report-ui")
        expect(page).to have_css(
          "dialog#report-config-dialog-sensemaking-report-ui button[name='quick_action'][value='sensemaking-report-ui']"
        )
        expect(page).not_to have_css ".quick-action-toggle"
      end
    end

    context "when summary has several scripts" do
      before do
        allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
          .with(:summary).and_return(["runner.ts", "other-summary"])
        allow(Sensemaker::ScriptRegistry).to receive(:scripts_for_logical_name)
          .with(:report).and_return(["sensemaking-report-ui"])
        allow(Sensemaker::ScriptRegistry).to receive(:backend_for).and_call_original
        allow(Sensemaker::ScriptRegistry).to receive(:backend_for).with("other-summary").and_return(:other)
        allow(Sensemaker::ScriptRegistry).to receive(:i18n_key).and_call_original
        allow(Sensemaker::ScriptRegistry).to receive(:i18n_key).with("other-summary").and_return("runner_ts")
      end

      it "opens a dropdown instead of submitting" do
        render_inline component

        toggle = ".quick-action-toggle[type='button'][aria-controls='sensemaker_summary_scripts']"

        expect(page).to have_css toggle, text: I18n.t("admin.sensemaker.new.generate_summary")
        expect(page).not_to have_css ".quick-action-toggle[name='quick_action']"
      end

      it "lists every script in the dropdown" do
        render_inline component

        expect(page).to have_css(
          "#sensemaker_summary_scripts button[name='quick_action'][value='runner.ts']"
        )
        expect(page).to have_css(
          "#sensemaker_summary_scripts button[name='quick_action'][value='other-summary']"
        )
      end
    end
  end

  describe "#script_option_label" do
    it "returns the localized script title" do
      expect(component.script_option_label("runner.ts"))
        .to eq(I18n.t("admin.sensemaker.scripts.runner_ts.title"))
    end
  end
end
