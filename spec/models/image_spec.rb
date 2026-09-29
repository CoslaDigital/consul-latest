require "rails_helper"

describe Image do
  let(:image) { create(:image, attachment: fixture_file_upload("clippy.jpg")) }

  it_behaves_like "image validations", "budget_investment_image"
  it_behaves_like "image validations", "budget_image"
  it_behaves_like "image validations", "proposal_image"

  it "stores attachments with Active Storage" do
    expect(image.attachment).to be_attached
    expect(image.attachment.filename).to eq "clippy.jpg"
  end

  describe "#variant" do
    it "processes variants with combine_options from old Active Storage URLs" do
      old_transformations = {
        combine_options: { gravity: "center", resize: "300x300^", crop: "300x300+0+0" }
      }

      expect { image.attachment.variant(old_transformations).processed }.not_to raise_error
    end

    it "preserves Rails validations for normal transformations" do
      unsafe_transformations = { system: "dangerous_command" }

      expect { image.attachment.variant(unsafe_transformations).processed }.to raise_error(
        ActiveStorage::Transformers::ImageProcessingTransformer::UnsupportedImageProcessingMethod
      )
    end

    it "validates operations unwrapped from combine_options" do
      legacy_with_unsafe = {
        combine_options: { system: "dangerous_command" }
      }

      expect { image.attachment.variant(legacy_with_unsafe).processed }.to raise_error(
        ActiveStorage::Transformers::ImageProcessingTransformer::UnsupportedImageProcessingMethod
      )
    end
  end
end
