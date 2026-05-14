class Shared::AgreeWithTermsOfServiceFieldComponent < ApplicationComponent
  attr_reader :form
  delegate :new_window_link_to, to: :helpers

  def initialize(form)
    @form = form
  end

  private

    def label
      t("form.accept_terms",
        policy: new_window_link_to(t("form.policy"), "/privacy"),
        conditions: new_window_link_to(t("form.conditions"), "/conditions"))
    end

    def rider
      "I confirm that I have read, understand and agree to the application criteria and have all relevant policies and processes in place."
    end
end
