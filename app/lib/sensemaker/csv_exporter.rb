require "csv"

module Sensemaker
  class CsvExporter
    EXPORT_HEADERS = %w[participant_id survey_text agrees disagrees passes author-id].freeze

    attr_reader :conversation

    def initialize(conversation, options = {})
      raise ArgumentError,
            "conversation must be a Sensemaker::Conversation" unless conversation.is_a?(Conversation)

      @conversation = conversation
    end

    def export_to_csv(file_path = nil)
      file_path ||= default_file_path
      FileUtils.mkdir_p(File.dirname(file_path))

      CSV.open(file_path, "w", write_headers: true, headers: self.class::EXPORT_HEADERS) do |csv|
        export_data.each do |row|
          csv << row
        end
      end

      file_path
    end

    def export_to_string
      CSV.generate(headers: true) do |csv|
        csv << self.class::EXPORT_HEADERS
        export_data.each do |row|
          csv << row
        end
      end
    end

    private

      def export_data
        data = []
        data.concat(comments_as_rows)
        data
      end

      def comments_as_rows
        items = @conversation.comments

        items.map do |item|
          [
            item_id(item),
            item.body,
            item.cached_votes_up || 0,
            item.cached_votes_down || 0,
            item_votes_neutral(item),
            item.user_id
          ]
        end
      end

      def item_id(item)
        if item.is_a?(CommentLikeItem)
          "item_#{item.id}"
        else
          "comment_#{item.id}"
        end
      end

      def item_votes_neutral(item)
        total = item.cached_votes_total || 0
        up = item.cached_votes_up || 0
        down = item.cached_votes_down || 0
        [total - up - down, 0].max
      end

      def default_file_path
        data_folder = Sensemaker::Paths.sensemaker_data_folder
        File.join(data_folder, "sensemaker-input.csv")
      end
  end
end
