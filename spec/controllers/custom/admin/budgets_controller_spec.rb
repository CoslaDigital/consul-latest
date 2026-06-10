require "rails_helper"

describe Admin::BudgetsController do
  # Assuming standard Consul factories for roles.
  # If your factories differ slightly, adjust these to match how you create PMs/Admins.
  let(:admin) { create(:administrator).user }
  let(:pm1) { create(:process_manager).user }
  let(:pm2) { create(:process_manager).user }

  # Create budgets authored by different users
  let!(:admin_budget) { create(:budget, author: admin) }
  let!(:pm1_budget) { create(:budget, author: pm1) }
  let!(:pm2_budget) { create(:budget, author: pm2) }

  describe "GET index" do
    context "when logged in as a Process Manager" do
      before { sign_in(pm1) }

      it "only loads the budgets authored by that specific Process Manager" do
        get :index

        # Process Manager 1 should only see their own budget
        expect(assigns(:budgets)).to include(pm1_budget)
        expect(assigns(:budgets)).not_to include(pm2_budget)
        expect(assigns(:budgets)).not_to include(admin_budget)
      end
    end

    context "when logged in as an Administrator" do
      before { sign_in(admin) }

      it "loads all budgets regardless of authorship" do
        get :index

        expect(assigns(:budgets)).to include(admin_budget, pm1_budget, pm2_budget)
      end
    end
  end

  describe "POST create" do
    context "when logged in as a Process Manager" do
      before { sign_in(pm1) }

      it "automatically assigns the current user as the author of the new budget" do
        # Note: adjust the params payload if your Budget model requires specific translation formats
        valid_params = {
          name: "Community Health Budget",
          currency_symbol: "€",
          phase: "informing",
          voting_style: "knapsack"
        }

        expect {
          post :create, params: { budget: valid_params }
        }.to change(Budget, :count).by(1)

        new_budget = Budget.last
        expect(new_budget.author).to eq(pm1)
      end
    end
  end

  describe "GET edit" do
    context "when logged in as a Process Manager" do
      before { sign_in(pm1) }

      it "allows access to edit their own budget" do
        get :edit, params: { id: pm1_budget.id }
        expect(response).to be_successful
      end

      it "raises a CanCan::AccessDenied error when attempting to edit another PM's budget" do
        expect {
          get :edit, params: { id: pm2_budget.id }
        }.to raise_error(CanCan::AccessDenied)
      end
    end

    context "when logged in as an Administrator" do
      before { sign_in(admin) }

      it "allows access to edit any budget" do
        get :edit, params: { id: pm1_budget.id }
        expect(response).to be_successful
      end
    end
  end

  describe "PUT publish" do
    context "when logged in as a Process Manager" do
      before { sign_in(pm1) }

      it "can publish their own drafting budget" do
        draft_budget = create(:budget, author: pm1, published: false)

        put :publish, params: { id: draft_budget.id }

        expect(draft_budget.reload.published).to be true
        expect(response).to redirect_to(admin_budget_path(draft_budget))
      end

      it "cannot publish another user's drafting budget" do
        other_draft_budget = create(:budget, author: pm2, published: false)

        expect {
          put :publish, params: { id: other_draft_budget.id }
        }.to raise_error(CanCan::AccessDenied)
      end
    end
  end
end
