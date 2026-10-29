require "rails_helper"

describe User do
  let(:user) { create(:user) }

  # Helper method to cleanly mock settings in memory without hitting the slow database
  def mock_setting(key, value)
    allow(Setting).to receive(:[]).with(key).and_return(value)
  end

  describe "Verification Pipeline Engine" do
    before do
      # Allow normal DB lookups for all other settings (like locales, etc.)
      allow(Setting).to receive(:[]).and_call_original

      # Start with a clean slate for our verification settings
      mock_setting("verification.require_residence", nil)
      mock_setting("verification.require_sms", nil)
      mock_setting("verification.require_letter", nil)
      mock_setting("verification.ys_requires_demographics", nil)
    end

    describe "#verification_pipeline" do
      it "builds the pipeline dynamically based on active settings" do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.require_sms", "1")
        # Letter remains nil

        expect(user.verification_pipeline).to eq([:residence, :sms])
      end

      it "skips settings that are disabled (nil)" do
        mock_setting("verification.require_residence", nil)
        mock_setting("verification.require_sms", nil)
        mock_setting("verification.require_letter", "1")

        expect(user.verification_pipeline).to eq([:letter])
      end

      it "grants instant verification to YS users if the demographics switch is off, skipping SMS" do
        mock_setting("verification.ys_requires_demographics", nil) # Turned OFF
        mock_setting("verification.require_sms", "1") # Globally ON

        allow(User).to receive(:valid_ys_document?).and_return(true)
        user.update!(document_number: "YS-1234")

        # Pipeline is empty because they get the early exit!
        expect(user.verification_pipeline).to eq([])
      end

      it "subjects YS users to global verification steps if the demographics switch is on" do
        mock_setting("verification.ys_requires_demographics", "1") # Turned ON
        mock_setting("verification.require_sms", "1") # Globally ON

        allow(User).to receive(:valid_ys_document?).and_return(true)
        user.update!(document_number: "YS-1234")

        # Pipeline catches them and adds global steps
        expect(user.verification_pipeline).to eq([:ys_demographics, :sms])
      end
    end

    describe "#pending_verification_steps" do
      it "accurately removes steps that have already been completed" do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.require_sms", "1")

        # Initially, both are pending
        expect(user.pending_verification_steps).to eq([:residence, :sms])

        # Complete Residence
        user.update!(residence_verified_at: Time.current)
        expect(user.pending_verification_steps).to eq([:sms])

        # Complete SMS
        user.update!(confirmed_phone: "07123456789")
        expect(user.pending_verification_steps).to eq([])
      end
    end
  end
end
