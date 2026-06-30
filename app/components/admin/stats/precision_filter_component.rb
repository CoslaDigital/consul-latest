class Admin::Stats::PrecisionFilterComponent < ApplicationComponent
  attr_reader :url, :precision

  def initialize(url:, precision:)
    @url = url
    @precision = precision
  end

  def dummy_setting
    OpenStruct.new(
      key: "precision",
      value: precision
    )
  end

  def precision_options
    [
      [t("stats.budgets.precisions.district"), 1],
      [t("stats.budgets.precisions.neighborhood"), 2],
      [t("stats.budgets.precisions.street"), 3],
      [t("stats.budgets.precisions.building"), 4]
    ]
  end
end
