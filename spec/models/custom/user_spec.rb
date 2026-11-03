require "rails_helper"

RSpec.describe User, type: :model do
  # Helper method to cleanly mock settings in memory without hitting the slow database
  def mock_setting(key, value)
    allow(Setting).to receive(:[]).with(key).and_return(value)
  end

  describe "Verification Pipeline Engine (Instance Methods)" do
    let(:user) { create(:user) }

    before do
      # Allow normal DB lookups for all other settings (like locales, feature.restrict_login_to_officials, etc.)
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

      it "skips demographics for YS users if the switch is off, but keeps global steps like SMS" do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.ys_requires_demographics", nil) # Turned OFF
        mock_setting("verification.require_sms", "1") # Globally ON

        allow(User).to receive(:valid_ys_document?).and_return(true)
        user.update!(document_number: "YS-1234")

        # Demographics is skipped, but SMS remains because it's globally ON
        expect(user.verification_pipeline).to eq([:sms])
      end

      it "subjects YS users to demographic and global steps if the demographics switch is on" do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.ys_requires_demographics", "1") # Turned ON
        mock_setting("verification.require_sms", "1") # Globally ON

        allow(User).to receive(:valid_ys_document?).and_return(true)
        user.update!(document_number: "YS-1234")

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

  describe ".log_in_or_create_ys_user - Soak Test: YS Creation Combinations (Class Method)" do
    let(:ys_card) { "9991111254367801" } # Trumptonshire mock card mapped in NEC_PREFIX_MAPPING
    let(:email) { "test@example.com" }

    before do
      # Ensure the geozone exists to avoid Geozone.find_by! raising an error during YS creation
      Geozone.find_or_create_by!(name: "ys_trumptonshire")

      # IMPORTANT FIX: Tell RSpec to allow standard DB lookups for any un-stubbed settings
      allow(Setting).to receive(:[]).and_call_original
    end

    context "when Demographics is ON, SMS is OFF, Letter is OFF" do
      before do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.ys_requires_demographics", "1")
        mock_setting("verification.require_sms", nil)
        mock_setting("verification.require_letter", nil)
        mock_setting("feature.user.skip_verification", nil)
      end

      it "requires ONLY ys_demographics" do
        user = User.log_in_or_create_ys_user(ys_card, email)

        expect(user.pending_verification_steps).to eq([:ys_demographics])
        expect(user.pipeline_complete?).to be false
      end
    end

    context "when Demographics is OFF, SMS is ON" do
      before do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.ys_requires_demographics", nil) # OFF
        mock_setting("verification.require_sms", "1")
        mock_setting("verification.require_letter", nil)
        mock_setting("feature.user.skip_verification", nil)
      end

      it "skips demographics (auto-stamps residence_verified_at) and requires ONLY sms" do
        user = User.log_in_or_create_ys_user(ys_card, email)

        expect(user.residence_verified_at).not_to be_nil
        expect(user.pending_verification_steps).to eq([:sms])
        expect(user.pipeline_complete?).to be false
      end
    end

    context "when ALL steps are ON (Demographics, SMS, Letter)" do
      before do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.ys_requires_demographics", "1")
        mock_setting("verification.require_sms", "1")
        mock_setting("verification.require_letter", "1")
        mock_setting("feature.user.skip_verification", nil)
      end

      it "queues demographics, sms, and letter in the correct order" do
        user = User.log_in_or_create_ys_user(ys_card, email)

        expect(user.pending_verification_steps).to eq([:ys_demographics, :sms, :letter])
        expect(user.pipeline_complete?).to be false
      end
    end

    context "when master skip_verification feature is ON" do
      before do
        mock_setting("verification.require_residence", "1")
        mock_setting("verification.ys_requires_demographics", "1")
        mock_setting("verification.require_sms", "1")
        mock_setting("feature.user.skip_verification", "1") # OVERRIDE
      end

      it "auto-stamps all verification levels and bypasses the pipeline entirely" do
        user = User.log_in_or_create_ys_user(ys_card, email)

        expect(user.residence_verified_at).not_to be_nil
        expect(user.level_two_verified_at).not_to be_nil
        expect(user.verified_at).not_to be_nil

        expect(user.pending_verification_steps).to be_empty
        expect(user.pipeline_complete?).to be true
      end
    end
  end
end
