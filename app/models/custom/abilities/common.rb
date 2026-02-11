load Rails.root.join("app", "models", "abilities", "common.rb")

module Abilities
  class Common
    alias_method :consul_initialize, :initialize # create a copy of the original method

    def initialize(user)
      consul_initialize(user) # call the original method
      cannot :create, Debate # undo the permission added in the original method
      can :create, Debate unless Setting.restrict_debate_creation?
    end
  end
end
