resource :account, controller: "account", only: [:show, :update]
  resource :two_factor_authentication, only: [:show, :create, :destroy] do
    post :enable, on: :member
    get :backup_codes, on: :collection
  end
end

resource :subscriptions, only: [:edit, :update]
