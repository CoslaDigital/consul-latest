load Rails.root.join("app", "models", "budget.rb")
class Budget < ApplicationRecord
  include Documentable
  has_many :questions, class_name: "Budget::Question"


end
