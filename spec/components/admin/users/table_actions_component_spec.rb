# spec/components/admin/users/table_actions_component_spec.rb
require "rails_helper"

describe Admin::Users::TableActionsComponent do
  context "when lockable is enabled" do
    before do
      allow(User).to receive(:devise_modules).and_return([:lockable])
    end

    it "renders a lock icon for an unlocked user" do
      user = build(:user)
      allow(user).to receive(:access_locked?).and_return(false)

      render_inline Admin::Users::TableActionsComponent.new(user)

      expect(page).to have_css ".unlocked-icon"
      expect(page).not_to have_css ".locked-icon"
    end

    it "renders an unlock icon for a locked user" do
      user = build(:user)
      allow(user).to receive(:access_locked?).and_return(true)

      render_inline Admin::Users::TableActionsComponent.new(user)

      expect(page).to have_css ".locked-icon"
      expect(page).not_to have_css ".unlocked-icon"
    end

    it "renders the correct aria label for an unlocked user" do
      user = build(:user)
      allow(user).to receive(:access_locked?).and_return(false)

      render_inline Admin::Users::TableActionsComponent.new(user)

      expect(page).to have_button I18n.t("admin.actions.lock")
    end

    it "renders the correct aria label for a locked user" do
      user = build(:user)
      allow(user).to receive(:access_locked?).and_return(true)

      render_inline Admin::Users::TableActionsComponent.new(user)

      expect(page).to have_button I18n.t("admin.actions.unlock")
    end
  end

  context "when lockable is disabled" do
    before do
      allow(User).to receive(:devise_modules).and_return([])
    end

    it "renders nothing" do
      user = build(:user)

      render_inline Admin::Users::TableActionsComponent.new(user)

      expect(page).not_to have_css ".locked-icon"
      expect(page).not_to have_css ".unlocked-icon"
    end
  end
end
