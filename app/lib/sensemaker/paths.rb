# frozen_string_literal: true

module Sensemaker
  module Paths
    def self.sensemaker_folder
      if Rails.env.test?
        Rails.root.join("tmp/sensemaker_test_folder")
      else
        Rails.root.join("vendor/sensemaking-tools")
      end
    end

    def self.sensemaker_venv
      sensemaker_folder.join("venv")
    end

    def self.sensemaker_bin
      sensemaker_venv.join("bin")
    end

    def self.sensemaking_cli(name)
      path = sensemaker_bin.join(name)
      unless File.file?(path) && File.executable?(path)
        raise "Sensemaker CLI not found or not executable: #{path}. " \
              "Run: bundle exec rake sensemaker:setup"
      end
      path
    end

    def self.node_modules_bin
      Rails.root.join("node_modules/.bin")
    end

    def self.node_cli(name)
      path = node_modules_bin.join(name)
      unless File.file?(path) && File.executable?(path)
        raise "Sensemaker Node CLI not found or not executable: #{path}. " \
              "Run: npm install"
      end
      path
    end

    def self.sensemaker_relative_data_folder
      if Rails.env.test?
        "tmp/sensemaker_test_folder/data"
      else
        Tenant.current_secrets.sensemaker_data_folder
      end
    end

    def self.sensemaker_data_folder
      Rails.root.join(sensemaker_relative_data_folder)
    end
  end
end
