module Sensemaker
  module Paths
    def self.stable_root
      # Forces the path to the 'current' symlink instead of a timestamped release
      if Rails.env.test?
        Rails.root
      else
        Pathname.new("/home/deploy/consul/current")
      end
    end

    def self.sensemaker_folder
      stable_root.join("vendor/sensemaking-tools")
    end

    def self.sensemaker_package_folder
      stable_root.join("node_modules/@cosla/sensemaking-tools")
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
      stable_root.join("node_modules/@cosla/sensemaking-web-ui")
    end
  end
end
