# app/components/concerns/stv_formatting.rb
#
# Shared numeric formatting for STV report components.
#
#   - Whole numbers render as integers ("2", not "2.0")
#   - Fractional values render to 4 decimal places, trailing zeros trimmed
#     (e.g. 3.142857 -> "3.1429", 1.5000 -> "1.5")
#
module StvFormatting
  extend ActiveSupport::Concern

  def format_votes(value)
    return "0" if value.nil?

    if value == value.to_i
      value.to_i.to_s
    else
      format("%.4f", value).sub(/0+\z/, "").sub(/\.\z/, "")
    end
  end
end
