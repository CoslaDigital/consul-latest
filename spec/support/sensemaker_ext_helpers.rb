# frozen_string_literal: true

module SensemakerExtTestHelpers
  REPORT_BUILDER_CONFIG_SCHEMA_FIXTURE = Rails.root.join(
    "spec/fixtures/files/sensemaker_ext/report_builder/schemas/config.v1.json"
  )

  def self.seed_report_builder_config_schema!
    destination = SensemakerExt::Paths.report_builder_config_schema
    FileUtils.mkdir_p(destination.dirname)
    FileUtils.cp(REPORT_BUILDER_CONFIG_SCHEMA_FIXTURE, destination)
  end
end

RSpec.shared_context "sensemaker report builder config schema" do
  before { SensemakerExtTestHelpers.seed_report_builder_config_schema! }
end
