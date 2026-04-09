class Offer < ApplicationRecord
  include Flaggable
  include Taggable
  include Sanitizable
  include Searchable
  include HasPublicAuthor
  include Imageable
  include Mappable
  include Notifiable

  # Soft deletion (matches Consul's standard setup)
  acts_as_paranoid column: :hidden_at
  include ActsAsParanoidAliases

  # Associations
  belongs_to :author, -> { with_hidden }, class_name: "User", inverse_of: :offers
  belongs_to :geozone, optional: true

  # The dating app connection
  has_many :proposal_matches, dependent: :destroy
  has_many :proposals, through: :proposal_matches

  # Existing Consul comment system
  has_many :comments, as: :commentable, inverse_of: :commentable, dependent: :destroy

  # State Machine for the Offer's lifecycle
  enum status: {
    available: 0,
    pending: 1, # Currently in talks with a Proposal
    claimed: 2 # Offer has been fulfilled/used up
  }

  # Validations
  validates :title, presence: true, length: { in: 4..150 }
  validates :description, presence: true
  validates :author, presence: true

  # Scopes for easy filtering
  scope :sort_by_created_at, -> { reorder(created_at: :desc) }
  scope :active, -> { where(status: :available) }

  # Search definition (integrating with Consul's pg_search)
  def searchable_values
    {
      title => "A",
      description => "C",
      author.username => "B",
      tag_list.join(" ") => "B",
      geozone&.name => "B"
    }
  end
end
