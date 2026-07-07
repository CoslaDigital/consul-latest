require "rails_helper"

describe Sensemaker::CsvExporter do
  let(:commentable) { create(:debate) }
  let(:conversation) { Sensemaker::Conversation.new("Debate", commentable.id) }
  let(:csv_exporter) { Sensemaker::CsvExporter.new(conversation) }

  describe "#export_to_csv" do
    it "exports the comments to a CSV file" do
      expect(csv_exporter.export_to_csv).to be_present
    end

    it "exports to the specified file path" do
      file_path = "/tmp/test-export.csv"
      result = csv_exporter.export_to_csv(file_path)
      expect(result).to eq(file_path)
      expect(File.exist?(file_path)).to be true
    end

    it "includes comment data in the CSV" do
      create(:comment, commentable: commentable, body: "Test comment")
      file_path = "/tmp/test-export.csv"

      csv_exporter.export_to_csv(file_path)
      csv_content = File.read(file_path)

      expect(csv_content).to include("Test comment")
      expect(csv_content).to include(Sensemaker::CsvExporter::EXPORT_HEADERS.to_csv.chomp)
    end

    it "uses participant_id and survey_text column names" do
      comment = create(:comment, commentable: commentable, body: "Test comment")
      file_path = "/tmp/test-export-headers.csv"

      csv_exporter.export_to_csv(file_path)
      rows = CSV.read(file_path, headers: true)

      expect(rows.headers).to eq(Sensemaker::CsvExporter::EXPORT_HEADERS)
      expect(rows.first["participant_id"]).to eq("comment_#{comment.id}")
      expect(rows.first["survey_text"]).to eq("Test comment")
    end
  end

  describe "#export_to_string" do
    it "exports the comments to a CSV string" do
      create(:comment, commentable: commentable, body: "Test comment")
      result = csv_exporter.export_to_string

      expect(result).to include("Test comment")
      expect(result).to include(Sensemaker::CsvExporter::EXPORT_HEADERS.to_csv.chomp)
    end
  end
end
