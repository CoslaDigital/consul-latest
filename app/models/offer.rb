class Offer < ApplicationRecord

  include Flaggable
  include Taggable
  include Searchable
  include HasPublicAuthor
  include Imageable
  # include Mappable
  include Notifiable

  include Filterable
  include Followable
  include Documentable
  include SDG::Relatable

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
  enum :status, {
    available: 0,
    pending: 1, # Currently being discussed
    claimed: 2, # Resource is fully used/gone
    withdrawn: 3 # Removed by author
  }, default: :available

  # Validations

  validates :terms_of_service, acceptance: { allow_nil: false }, on: :create
  validates :title, presence: true, length: { in: 4..150 }
  validates :description, presence: true
  validates :author, presence: true

  # Scopes for easy filtering
  scope :sort_by_created_at, -> { reorder(created_at: :desc) }
  scope :available, -> { where(status: :available) }
  scope :pending, -> { where(status: :pending) }
  scope :claimed, -> { where(status: :claimed) }

  scope :active, -> { where(status: [:available, :pending]) }
  scope :withdrawn, -> { where(status: :withdrawn) }
  scope :archived, -> { where(status: [:claimed, :withdrawn]) }

  scope :most_active, -> { order(comments_count: :desc, created_at: :desc) }
  scope :newest, -> { order(created_at: :desc) }

  scope :last_week, -> { where(created_at: 7.days.ago..) }

  after_create :notify_admin_new_offer

  def self.search(terms)
    pg_search(terms)
  end
  def searchable_values
    {
      title => "A",
      description => "C",
      author.username => "B",
      tag_list.join(" ") => "B",
      geozone&.name => "B"
    }
  end

  def after_hide
    tags.each { |t| t.decrement_custom_counter_for("Offer") }
  end

  def after_restore
    tags.each { |t| t.increment_custom_counter_for("Offer") }
  end

  def active?
    status == "available" && hidden_at.nil?
  end

  private

    def notify_admin_new_offer
      Mailer.new_offer_admin_notification(self).deliver_later
    end
end
