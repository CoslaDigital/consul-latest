# app/components/admin/collaborations/index_component.rb
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
        case status.to_sym
        when :fulfilled then "success"
        when :confirmed then "info"
        when :pending, :accepted then "warning"
        when :rejected then "alert"
        else "secondary"
        end
      end

      def can_force_fulfill?(match)
        !match.fulfilled? && !match.rejected?
      end

      def can_hide_offer?(offer)
        !offer.hidden?
      end
    end
  end
end
