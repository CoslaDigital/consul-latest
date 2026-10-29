require "rails_helper"

describe VerificationHelper do
  describe "#mask_phone" do
    it "masks a phone" do
      expect(mask_phone("612345678")).to eq("******678")
    end
  end

  describe "#mask_email" do
    it "masks a long email address" do
      expect(mask_email("isabel@example.com")).to eq("isa***@example.com")
      expect(mask_email("antonio.perez@example.com")).to eq("ant**********@example.com")
    end

    it "masks a short email address" do
      expect(mask_email("an@example.com")).to eq("an@example.com")
      expect(mask_email("ana@example.com")).to eq("ana@example.com")
      expect(mask_email("aina@example.com")).to eq("ain*@example.com")
    end
  end

  describe ".postal_code_allowed_by_settings?" do
    it "returns true immediately if the global setting is completely blank" do
      allow(Setting).to receive(:[]).with("postal_codes").and_return("")
      expect(VerificationHelper.postal_code_allowed_by_settings?("EH1 1AA")).to be true
    end

    it "strips spaces and casing to match exactly" do
      allow(Setting).to receive(:[]).with("postal_codes").and_return("EH1 1AA, G1 1AB")

      # Should match despite weird user input formatting
      expect(VerificationHelper.postal_code_allowed_by_settings?("eh11aa")).to be true
      expect(VerificationHelper.postal_code_allowed_by_settings?(" EH1  1AA ")).to be true
    end

    it "allows a partial prefix match (e.g. FK10 allows FK10 2FB)" do
      allow(Setting).to receive(:[]).with("postal_codes").and_return("FK10")

      expect(VerificationHelper.postal_code_allowed_by_settings?("FK10 2FB")).to be true
      expect(VerificationHelper.postal_code_allowed_by_settings?("fk103zz")).to be true

      # Should reject something outside the prefix
      expect(VerificationHelper.postal_code_allowed_by_settings?("FK11 2FB")).to be false
    end

    it "handles complex alphanumeric ranges" do
      allow(Setting).to receive(:[]).with("postal_codes").and_return("ab101aa:ab129zz")

      expect(VerificationHelper.postal_code_allowed_by_settings?("AB11 5BB")).to be true
      expect(VerificationHelper.postal_code_allowed_by_settings?("AB09 1AA")).to be false # Too low
      expect(VerificationHelper.postal_code_allowed_by_settings?("AB13 1AA")).to be false # Too high
    end

    it "can handle a mix of exact matches, prefixes, and ranges in one comma-separated list" do
      allow(Setting).to receive(:[]).with("postal_codes").and_return("FK10, G1 1AB, EH1:EH5")

      expect(VerificationHelper.postal_code_allowed_by_settings?("FK10 2FB")).to be true # Hit prefix
      expect(VerificationHelper.postal_code_allowed_by_settings?("G1 1AB")).to be true # Hit exact
      expect(VerificationHelper.postal_code_allowed_by_settings?("EH3 4QQ")).to be true # Hit range
      expect(VerificationHelper.postal_code_allowed_by_settings?("M1 1AA")).to be false # Miss
    end
  end
end
