class Shared::BasicInfoComponent < ApplicationComponent
  delegate :namespace, to: :helpers
  attr_reader :record, :user_viewer

  # Add user_viewer: nil to the arguments
  def initialize(record, user_viewer: nil)
    @record = record
    @user_viewer = user_viewer
  end

  private

    def comments_path
      if namespace == "management"
        management_polymorphic_path(record, anchor: "comments")
      else
        polymorphic_path(record, anchor: "comments")
      end
    end

    def date
      time_tag record.created_at.to_date, format: :default
    end
end
