class Admin::TableActionsComponent < ApplicationComponent
  attr_reader :record, :options

  def initialize(record, **options)
    @record = record
    @options = options
  end

  def action(action_name, **)
    render Admin::ActionComponent.new(action_name, record, "aria-label": true, **)
  end

  private

    def actions
      options[:actions] || [:edit, :destroy]
    end

    def edit_text
      options[:edit_text]
    end

    def edit_path
      options[:edit_path]
    end

    def edit_options
      options[:edit_options] || {}
    end

    def destroy_text
      options[:destroy_text]
    end

    def destroy_path
      options[:destroy_path]
    end

    def destroy_options
      {
        confirm: options[:destroy_confirmation] || true
      }.merge(options[:destroy_options] || {})
    end

    # New Mutual Aid Actions (Accept/Reject)
    def accept_text
      options[:accept_text];
    end

    def accept_path
      options[:accept_path];
    end

    def accept_options
      { method: :patch }.merge(options[:accept_options] || {})
    end

    def reject_text
      options[:reject_text];
    end

    def reject_path
      options[:reject_path];
    end

    def reject_options
      { method: :patch }.merge(options[:reject_options] || {})
    end

    def confirm_path
      options[:confirm_path];
    end

    def confirm_options
      { method: :patch }.merge(options[:confirm_options] || {})
    end

    def fulfill_path
      options[:fulfill_path];
    end

    def fulfill_options
      {
        method: :patch,
        confirm: helpers.t("proposals.show.confirm_fulfillment_check")
      }.merge(options[:fulfill_options] || {})
    end
end
