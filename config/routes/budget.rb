resources :budgets, only: [:show, :index] do
  collection do
    get :select
    get :select_headings
    get :budget_headings, defaults: { format: :json }
  end
  resources :groups, controller: "budgets/groups", only: [:show, :index]
  resources :investments, controller: "budgets/investments" do
    member do
      put :flag
      put :unflag
    end

    collection { get :suggest }

    resources :votes, controller: "budgets/investments/votes", only: [:create, :destroy]
  end

  resource :ballot, only: :show, controller: "budgets/ballots" do
    resources :lines, controller: "budgets/ballot/lines", only: [:create, :destroy]
  end

  resource :results, only: :show, controller: "budgets/results"
  resource :stats, only: :show, controller: "budgets/stats"
  resource :executions, only: :show, controller: "budgets/executions"
end
