# Load the original core file
load Rails.root.join("app", "models", "abilities", "administrator.rb")

module CustomAdministratorAbilities
  def initialize(user)
    # Run the original abilities first
    super

    # Add our new custom abilities for User CRUD
    can [:create, :update, :credentials], User
  end
end

# Prepend the module to inject the new rules
Abilities::Administrator.prepend(CustomAdministratorAbilities)
