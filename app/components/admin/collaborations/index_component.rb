module Admin
  module Collaborations
    class IndexComponent < ViewComponent::Base
      attr_reader :matches, :offers
      delegate :paginate, to: :helpers

      def initialize(matches:, offers:)
        @matches = matches
        @offers = offers
      end

      # Public methods are accessible to the template
      def status_label_class(status)
        return "secondary" if status.blank?

        case status.to_sym
        when :fulfilled then "success"
        when :confirmed then "info"
        when :pending, :accepted then "warning"
        when :rejected then "alert"
        else "secondary" # This perfectly handles our new "unmatched" state
        end
      end

      def can_force_fulfill?(match)
        !match.fulfilled? && !match.rejected?
      end

      def can_hide_offer?(offer)
        !offer.hidden?
      end

      # NEW: Safely fetches the statuses of any matches connected to this offer
      def offer_match_statuses(offer)
        statuses = ProposalMatch.where(offer_id: offer.id).pluck(:status).uniq
        statuses.any? ? statuses : ["unmatched"]
      end
    end
  end
end
