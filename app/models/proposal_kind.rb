# app/models/proposal_kind.rb
class ProposalKind < ApplicationRecord
  has_many :proposals, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug

  private

    def generate_slug
      self.slug ||= name&.parameterize
    end
end
