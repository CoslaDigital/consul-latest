scope module: :verification do
  resource :residence, controller: "residence", only: [:new, :create]

  # ADD THIS LINE for the new YS demographics form
  resource :ys_demographic, controller: "ys_demographics", only: [:new, :create]

  resource :sms, controller: "sms", only: [:new, :create, :edit, :update]
  resource :verified_user, controller: "verified_user", only: [:show]
  resource :email, controller: "email", only: [:show, :create]
  resource :letter, controller: "letter", only: [:new, :create, :show, :edit, :update]
end

resource :verification, controller: "verification", only: [:show]
