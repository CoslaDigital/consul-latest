# load Rails.root.join("app", "controllers", "verification", "ys_demographics_controller.rb")

class Verification::YsDemographicsController < ApplicationController
  before_action :authenticate_user!
  skip_authorization_check

  def new
    @ys_demographic = Verification::YsDemographic.new(user: current_user)
  end

  def create
    @ys_demographic = Verification::YsDemographic.new(ys_params.merge(user: current_user))

    if @ys_demographic.save
      redirect_to verification_path, notice: "Verification complete."
    else
      render :new
    end
  end

  private

    def ys_params
      params.require(:ys_demographic).permit(:date_of_birth, :postal_code, :terms_of_service)
    end
end
