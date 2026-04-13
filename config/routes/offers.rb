# 1. Standard CRUD for the  Offers model
resources :offers do
  get :mine, on: :collection
end

# 2. Routes to handle the Matchmaking / Collaboration Requests
resources :proposal_matches, only: [:create, :destroy] do
  member do
    patch :accept # "Swipe Right" - Approve the request
    patch :reject # "Swipe Left" - Decline the request
    patch :confirm
    patch :fulfill # Mark the collaboration as completed
  end
end
