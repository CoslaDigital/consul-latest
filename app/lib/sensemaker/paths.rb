module Sensemaker
  module Paths
    def self.sensemaker_package_folder
      if Rails.env.test?
        Rails.root.join("tmp/sensemaker_test_folder/package")
      else
        Rails.root.join("node_modules/@cosla/sensemaking-tools")
      end
    end

    def self.sensemaker_folder
      if Rails.env.test?
        Rails.root.join("tmp/sensemaker_test_folder")
      else
        Rails.root.join("vendor/sensemaking-tools")
      end
    end

    def self.sensemaker_relative_data_folder
      if Rails.env.test?
        "tmp/sensemaker_test_folder/data"
      else
        Tenant.current_secrets.sensemaker_data_folder
      end
    end

    def self.sensemaker_data_folder
      data_path = sensemaker_relative_data_folder

      # 1. Check if it's already an absolute path (starts with /)
      if Pathname.new(data_path).absolute?
        Pathname.new(data_path)
      else
        # 2. If relative, join it to the SHARED folder, not Rails.root
        # This ensures files persist across deployments.
        Rails.root.join("../../shared", data_path).expand_path
      end
    end

    def self.visualization_folder
      if Rails.env.test?
        Rails.root.join("tmp/sensemaker_test_folder/web-ui")
      else
        Rails.root.join("node_modules/@cosla/sensemaking-web-ui")
      end
    end
  end
end
