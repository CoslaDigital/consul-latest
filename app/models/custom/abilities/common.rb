load Rails.root.join("app", "models", "abilities", "common.rb")

module Abilities
  class Common
    alias_method :consul_initialize, :initialize # create a copy of the original method

    def initialize(user)
      consul_initialize(user) # call the original method
      cannot :create, Debate # undo the permission added in the original method
      can :create, Debate unless Setting.restrict_debate_creation?

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
    end
  end
end
