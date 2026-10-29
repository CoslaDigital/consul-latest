require "rails_helper"

describe VerificationController do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "GET show" do
    it "redirects to the residence form when it is the next step" do
      allow_any_instance_of(User).to receive(:pending_verification_steps).and_return([:residence, :sms])

      get :show

      expect(response).to redirect_to(new_residence_path)
    end

    it "redirects to the new sms form when residence is done but sms is pending" do
      allow_any_instance_of(User).to receive(:pending_verification_steps).and_return([:sms])
      allow_any_instance_of(User).to receive(:verification_sms_sent?).and_return(false)

      get :show

      expect(response).to redirect_to(new_sms_path)
    end

    it "redirects to the edit sms form if an sms code was already sent" do
      allow_any_instance_of(User).to receive(:pending_verification_steps).and_return([:sms])
      allow_any_instance_of(User).to receive(:verification_sms_sent?).and_return(true)

      get :show

      expect(response).to redirect_to(edit_sms_path)
    end

    it "promotes the user and redirects to account when the pipeline is empty" do
      allow_any_instance_of(User).to receive(:pending_verification_steps).and_return([])

      get :show

      # Proves the db timestamp was stamped
      expect(user.reload.verified_at).to be_present
      # Proves they were sent to the account page
      expect(response).to redirect_to(account_path)
    end
  end
end
