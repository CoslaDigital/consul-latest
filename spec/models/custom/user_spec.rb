require "rails_helper"

describe User do
  let(:user) { create(:user) }

  describe "Verification Pipeline Engine" do
    before do
      # Start with a clean slate of settings for each test
      Setting["verification.require_residence"] = nil
      Setting["verification.require_sms"] = nil
      Setting["verification.require_letter"] = nil
      Setting["verification.ys_requires_demographics"] = nil
    end

    describe "#verification_pipeline" do
      it "builds the pipeline dynamically based on active settings" do
        Setting["verification.require_residence"] = "1"
        Setting["verification.require_sms"] = "1"
        # Letter remains nil

        expect(user.verification_pipeline).to eq([:residence, :sms])
      end

      it "skips settings that evaluate to empty or false" do
        Setting["verification.require_residence"] = "0"
        Setting["verification.require_sms"] = ""
        Setting["verification.require_letter"] = "1"

        expect(user.verification_pipeline).to eq([:letter])
      end
    end

    describe "#pending_verification_steps" do
      it "accurately removes steps that have already been completed" do
        Setting["verification.require_residence"] = "1"
        Setting["verification.require_sms"] = "1"

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
