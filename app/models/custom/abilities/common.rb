module Abilities
  class Common
    include CanCan::Ability

    def initialize(user)
      merge Abilities::Everyone.new(user)

      can [:read, :update], User, id: user.id

      can :read, Debate
      can :update, Debate do |debate|
        debate.editable_by?(user)
      end
      
      
      
      can :read, Proposal
      can :update, Proposal do |proposal|
        proposal.editable_by?(user)
      end
      can :publish, Proposal do |proposal|
        proposal.draft? && proposal.author.id == user.id && !proposal.retired?
      end
      can :dashboard, Proposal do |proposal|
        proposal.author.id == user.id
      end
      can :manage_polls, Proposal do |proposal|
        proposal.author.id == user.id
      end
      can :manage_mailing, Proposal do |proposal|
        proposal.author.id == user.id
      end
      can :manage_poster, Proposal do |proposal|
        proposal.author.id == user.id
      end

      can :results, Poll do |poll|
        poll.related&.author&.id == user.id
      end

      can [:retire_form, :retire], Proposal, author_id: user.id

      can :read, Legislation::Proposal
      can [:retire_form, :retire], Legislation::Proposal, author_id: user.id

      can :create, Comment
      can :create, Debate
      can [:create, :created], Proposal
      can :create, Legislation::Proposal

      can :hide, Comment, user_id: user.id

      can :suggest, Debate
      can :suggest, Proposal
      can :suggest, Legislation::Proposal
      can :suggest, Tag

      can [:flag, :unflag], Comment
      cannot [:flag, :unflag], Comment, user_id: user.id

      can [:flag, :unflag], Debate
      cannot [:flag, :unflag], Debate, author_id: user.id

      can [:flag, :unflag], Proposal
      cannot [:flag, :unflag], Proposal, author_id: user.id

      can [:flag, :unflag], Legislation::Proposal
      cannot [:flag, :unflag], Legislation::Proposal, author_id: user.id

      can [:flag, :unflag], Budget::Investment
      cannot [:flag, :unflag], Budget::Investment, author_id: user.id

      can [:create, :destroy], Follow, user_id: user.id

      can [:destroy], Document do |document|
        document.documentable_type != "Poll::Question::Option" && document.documentable&.author_id == user.id
      end

      can [:destroy], Image do |image|
        image.imageable_type != "Poll::Question::Option" && image.imageable&.author_id == user.id
      end

      can [:create, :destroy], DirectUpload

      unless user.organization?
        can [:create, :destroy], ActsAsVotable::Vote, voter_id: user.id, votable_type: "Debate"
        can [:create, :destroy], ActsAsVotable::Vote, voter_id: user.id, votable_type: "Comment"
      end

      can :create, Legislation::Answer if  user.organization&.verified?
  

        can :read, Budget::Investment::Answer, budget_question: { is_private: false }
 
        can :read, Budget::Investment::Answer, budget_question: { is_private: true }, investment: { author_id: user.id }
  
      # A user can manage a milestone if its parent ('milestoneable')
        # has a user_id that matches their own.
        # The :edit permission is automatically granted if the user can :update.
        can [:update, :destroy], Milestone do |milestone|
  # --- Start of Debugging Log ---
  puts "\n" # Adds a space in the log to make it easy to find
  puts "--- Checking Milestone Permissions for User ##{user.id} ---"
  puts "Milestone ID: #{milestone.id}"

  if milestone.milestoneable.present?
    puts "Parent Object: #{milestone.milestoneable.class.name} ##{milestone.milestoneable.id}"
    puts "Parent Author ID: #{milestone.milestoneable.author_id}"
  else
    puts "Parent Object: nil"
  end

  puts "Current User ID: #{user.id}"

  # This variable will hold the final decision
  decision = milestone.milestoneable&.author_id == user.id

  puts "Decision (IDs Match?): #{decision}"
  puts "--- End of Check ---\n"
  # --- End of Debugging Log ---

  decision # The rule returns the final decision
end

        # 2. Permission to CREATE milestones for their own investments
        # A user can create a milestone if they are the author of the parent investment.
        can :create, Milestone do |milestone|
          milestone.milestoneable.author_id == user.id
        end
        
        # Allow users to create an Image if its parent's author is the user
can :create, Image do |image|
  image.imageable&.author_id == user.id
end

# Allow users to create a Document if its parent's author is the user
can :create, Document do |document|
  document.documentable&.author_id == user.id
end
          
      if  user.organization&.verified?
        can :create, Budget::Investment,  budget: { phase: "accepting" }
        can :update, Budget::Investment,  budget: { phase: "accepting" }, author_id: user.id
        can :suggest, Budget::Investment, budget: { phase: "accepting" }
        can :destroy, Budget::Investment, budget: { phase: ["accepting", "reviewing"] }, author_id: user.id
      end
      if user.level_two_or_three_verified?
        can :vote, Proposal, &:published?

        can [:create, :destroy], ActsAsVotable::Vote, voter_id: user.id, votable_type: "Legislation::Proposal"

        can :create, Legislation::Answer

        can :create, Budget::Investment,  budget: { phase: "accepting" }
        can :update, Budget::Investment,  budget: { phase: "accepting" }, author_id: user.id
        can :suggest, Budget::Investment, budget: { phase: "accepting" }
        can :destroy, Budget::Investment, budget: { phase: ["accepting", "reviewing"] }, author_id: user.id
        can [:create, :destroy], ActsAsVotable::Vote,
            voter_id: user.id,
            votable_type: "Budget::Investment",
            votable: { budget: { phase: "selecting" }}

        can [:show, :create], Budget::Ballot,          budget: { phase: "balloting" }
        can [:create, :destroy], Budget::Ballot::Line, budget: { phase: "balloting" }

        can :create, DirectMessage
        can :show, DirectMessage, sender_id: user.id

        can :answer, Poll do |poll|
          poll.answerable_by?(user)
        end
        can :answer, Poll::Question do |question|
          question.answerable_by?(user)
        end
        can :destroy, Poll::Answer do |answer|
          answer.author == user && answer.question.answerable_by?(user)
        end
      end

      can [:create, :show], ProposalNotification, proposal: { author_id: user.id }

      can [:create], Topic
      can [:update, :destroy], Topic, author_id: user.id

      can :disable_recommendations, [Debate, Proposal]
    end
  end
end
