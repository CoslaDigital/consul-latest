class MyAreaController < ApplicationController
  before_action :authenticate_user!
  skip_authorization_check

  def show
    @geozone = current_user.geozone

    # Safely route standard users without a geozone to the homepage
    # instead of forcing them into their account settings.
    unless @geozone
      redirect_to root_path, notice: "Please select a local area in your account settings to view your local dashboard."
      return
    end

    # Format the name cleanly (removes the "ys_" prefix if it exists)
    @local_authority_name = @geozone.name.gsub("ys_", "").titleize

    # Fetch all budgets that have at least one heading assigned to the user's geozone
    @local_budgets = Budget.joins(groups: :headings)
                           .where(budget_headings: { geozone_id: @geozone.id })
                           .where(published: true) # Only show published budgets
                           .distinct
                           .order(created_at: :desc)

    # Segment the budgets by their current phase using clean %w[] literals
    @active_voting = @local_budgets.where(phase: "balloting")
    @upcoming = @local_budgets.where(phase: %w[informing accepting reviewing selecting valuating publishing_prices])
    @past_results = @local_budgets.where(phase: %w[reviewing_ballots finished])
  end
end
