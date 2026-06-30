load Rails.root.join("app", "models", "abilities", "common.rb")

module Abilities
  class Common
    alias_method :consul_initialize, :initialize

    def initialize(user)
      consul_initialize(user)

      return if user.blank?

      if Setting.can_edit_milestones?
      can [:update, :destroy], Milestone do |milestone|
        parent = milestone.milestoneable
        parent.present? &&
          parent.respond_to?(:author_id) &&
          parent.author_id == user.id
      end

      # 2. Permission to CREATE milestones
      can :create, Milestone do |milestone|
        parent = milestone.milestoneable
        parent.present? &&
          parent.respond_to?(:author_id) &&
          parent.author_id == user.id
      end
      end

      cannot :create, Debate
      can :create, Debate unless Setting.restrict_debate_creation?
    end
  end
end
