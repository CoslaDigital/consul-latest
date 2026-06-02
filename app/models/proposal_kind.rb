class ProposalKind < ApplicationRecord
  has_many :proposals, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug
  after_save :ensure_single_default, if: :default?
  after_destroy :fallback_default_assignment

  # Scopes
  # scope :default_kind, -> { find_by(default: true) || first }

  def self.default_kind
    find_by(default: true) || first
  end

  private

    def generate_slug
      if name_changed? || slug.blank?
        self.slug = name&.parameterize
      end
    end

    def ensure_single_default
      ProposalKind.where.not(id: id).update_all(default: false)
    end

    def fallback_default_assignment
      if ProposalKind.any? && !ProposalKind.exists?(default: true)
        ProposalKind.first.update!(default: true)
      end
    end
end
