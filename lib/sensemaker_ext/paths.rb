# frozen_string_literal: true

module SensemakerExt
  module Paths
    def self.report_builder_folder
      if Rails.env.test?
        Rails.root.join("tmp/sensemaker_test_folder/report-builder")
      else
        Rails.root.join("node_modules/@cosla/sensemaking-report-builder")
      end
    end

    def self.report_builder_config_schema
      report_builder_folder.join("schemas/config.v1.json")
    end
  end
end
