load Rails.root.join("app", "models", "budget.rb")

class Budget < ApplicationRecord
  include Documentable

  belongs_to :author, class_name: "User", optional: true
  has_many :questions, class_name: "Budget::Question"


end
