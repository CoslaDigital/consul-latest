load Rails.root.join("app", "models", "proposal.rb")

class Proposal < ApplicationRecord
  
  scope :for_render,               -> { includes(:tags) }
  scope :sort_by_hot_score,        -> { reorder(hot_score: :desc) }
  scope :sort_by_confidence_score, -> { reorder(confidence_score: :desc) }
  scope :sort_by_created_at,       -> { reorder(created_at: :desc) }
  scope :sort_by_most_commented,   -> { reorder(comments_count: :desc) }
  scope :sort_by_relevance,        -> { all }
  scope :sort_by_flags,            -> { order(flags_count: :desc, updated_at: :desc) }
  scope :sort_by_archival_date,    -> { archived.sort_by_confidence_score }
  scope :sort_by_recommendations,  -> { order(cached_votes_up: :desc) }
  scope :sort_by_alphabetical,   -> {
    translations_table = Proposal::Translation.arel_table
    with_translations(I18n.locale)
    .reorder(translations_table[:title].lower.asc)
    }
  
  
  def self.proposals_orders(user)
    orders = %w[hot_score created_at alphabetical relevance archival_date]

    if Setting["feature.user.recommendations_on_proposals"] && user&.recommended_proposals
      orders << "recommendations"
    end

    orders
  end
  
  
  

  def formatted_amount(amount)
    ActionController::Base.helpers.number_to_currency(amount,
                                                      precision: 0,
                                                      locale: I18n.locale,
                                                      unit: "£")
  end
  
  def formatted_price
      formatted_amount(price)
    end


  protected

    def set_responsible_name
      if author&.document_number?
        self.responsible_name = author.document_number
      end
    end
end
