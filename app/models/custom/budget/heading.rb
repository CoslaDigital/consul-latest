load Rails.root.join("app","models","budget","heading.rb")
class Budget
  class Heading < ApplicationRecord

    include Documentable

  end
end
