load Rails.root.join("app", "models", "abilities", "common.rb")

module Abilities
  class Common
    alias_method :consul_initialize, :initialize

    def initialize(user)
      consul_initialize(user)

      return if user.blank?

      can [:update, :destroy], Milestone do |milestone|
        parent = milestone.milestoneable
        # Guard: Must have parent, parent must have author_id, author_id must match
        parent.present? &&
          parent.respond_to?(:author_id) &&
          parent.author_id == user.id
      end

      # 2. Permission to CREATE milestones
      can :create, Milestone do |milestone|
        parent = milestone.milestoneable
        # This handles Milestone.new(milestoneable: @investment/@proposal)
        parent.present? &&
          parent.respond_to?(:author_id) &&
          parent.author_id == user.id
      end

      cannot :create, Debate
      can :create, Debate unless Setting.restrict_debate_creation?
    end
  end
end
