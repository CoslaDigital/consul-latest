module Abilities
  class Everyone
    include CanCan::Ability

    def initialize(user)
      # 1. Fallback for guests if not explicitly passed by the application controller
      user ||= User.new

      # 2. Check our new feature flag
      require_login = Setting["feature.require_login_to_view_processes"].present?

      # 3. Determine if the current visitor is a guest
      guest_user = !user.persisted?

      # 4. If the feature is ON and the user is a GUEST, do not grant these abilities.
      # (If they are logged in, or the feature is off, they get full read access)
      unless require_login && guest_user

        can [:read, :map], Debate
        can [:read, :map, :summary, :share], Proposal
        can :read, Comment
        can :read, Poll
        can :results, Poll, id: Poll.expired.results_enabled.not_budget.ids
        can :stats, Poll, id: Poll.expired.stats_enabled.not_budget.ids
        can :read, Poll::Question
        can :read, User
        can [:read, :welcome], Budget
        can [:read], Budget
        can [:read], Budget::Group
        can [:read, :print], Budget::Investment
        can :read_results, Budget, id: Budget.finished.results_enabled.ids

        if Sensemaker.enabled?
          can :read_sensemaking, Budget, id: Budget.finished.sensemaking_enabled.ids
        end

        can :read_stats, Budget, id: Budget.valuating_or_later.stats_enabled.ids
        can :read_executions, Budget, phase: "finished"
        can [:index, :read, :debate, :draft_publication, :allegations, :result_publication,
             :proposals, :milestones], Legislation::Process, published: true

        can :summary, Legislation::Process do |process|
          process.summary_publication_enabled? &&
            (process.summary_publication_date.nil? || process.summary_publication_date <= Date.current) &&
            process.id.in?(Legislation::Process.published.where(summary_publication_enabled: true).ids)
        end

        can [:read, :changes, :go_to_version], Legislation::DraftVersion
        can [:read], Legislation::Question
        can [:read, :share], Legislation::Proposal
        can [:search, :comments, :read, :create, :new_comment], Legislation::Annotation
        can :read, Sensemaker::Job, published: true
        can [:read, :help], ::SDG::Goal
        can :read, ::SDG::Phase
        can [:read], Offer, hidden_at: nil

      end
    end
  end
end
