require "shellwords"

namespace :sensemaker do
  desc "Setup Sensemaker Integration"
  task setup: :environment do
    logger = ApplicationLogger.new
    logger.info "Setting up Sensemaker Integration..."
    setup_sensemaker_app_prerequisites(logger)
    with_sensemaker_tenant(logger, "Setting up") { |lgr| setup_for_tenant(lgr) }
  end

  desc "Check if sensemaker-tools dependencies are available"
  task check_dependencies: :environment do
    logger = ApplicationLogger.new
    check_dependencies(logger)
  end

  desc "Verify Sensemaker installation"
  task verify: :environment do
    logger = ApplicationLogger.new
    logger.info "Verifying Sensemaker installation..."
    with_sensemaker_tenant(logger, "Verifying") { |lgr| verify_installation(lgr) }
  end

  private

    def with_sensemaker_tenant(logger, action_prefix)
      tenant_schema = ENV["CONSUL_TENANT"]
      if tenant_schema.present?
        logger.info "#{action_prefix} for tenant: #{tenant_schema}"
        unless Tenant.exists?(schema: tenant_schema)
          err_msg = "Tenant '#{tenant_schema}' not found. Available: #{Tenant.pluck(:schema).join(", ")}"
          logger.warn err_msg
          raise "Tenant '#{tenant_schema}' not found"
        end
        Tenant.switch(tenant_schema) { yield logger }
      else
        logger.info "No tenant specified, using default tenant"
        yield logger
      end
    end

    def setup_sensemaker_app_prerequisites(logger)
      sensemaker_path = Sensemaker::Paths.sensemaker_folder

      check_dependencies(logger)
      ensure_python_venv_and_package(logger)

      logger.info "Using sensemaker folder: #{sensemaker_path}"
      logger.info "Using Python venv: #{Sensemaker::Paths.sensemaker_venv}"

      setup_sensemaker_directory(sensemaker_path, logger)
      verify_python_cli_available(logger)
      check_key_file(logger)
    end

    def verify_installation(logger)
      check_env_variables(logger)
      check_dependencies(logger)
      check_directories(logger)
      check_key_file(logger)
      check_package(logger)
      check_is_enabled(logger)
      check_sensemaker_cli(logger)
      logger.info "Sensemaker installation verified you can now use the Sensemaker Tools."
    end

    def check_env_variables(logger)
      logger.info "Checking environment variables..."

      if Tenant.current_secrets.sensemaker_data_folder.blank?
        logger.warn "✗ sensemaker_data_folder not found. Please provide it in the tenant secrets."
        abort "Error: sensemaker_data_folder is required. Please check the logs."
      end
      logger.info "✓ sensemaker_data_folder found"

      config = runtime_config
      unless config.cli_supported?
        message = if config.adapter == "ollama"
                    "Ollama is not supported by the Python Sensemaker tools. " \
                      "Select Gemini, Vertex AI, or an OpenAI-compatible provider in Admin → Settings → LLM."
                  else
                    "Sensemaker LLM provider is not supported. Current provider: " \
                      "#{config.provider.presence || "(not set)"}."
                  end
        logger.warn "✗ #{message}"
        abort "Error: #{message}"
      end
      logger.info "✓ Supported Sensemaker adapter selected: #{config.adapter}."

      if config.adapter == "vertex" && config.vertex_project_id.blank?
        logger.warn "✗ Vertex AI is not configured. Please set tenant secrets " \
                    "llm.vertexai_project_id (and optionally vertexai_location)."
        abort "Error: Vertex AI configuration not found. Please check the logs."
      end
      logger.info "✓ Adapter configuration is present."

      if config.model.blank?
        logger.warn "✗ Sensemaker requires an LLM model to be selected. Set it in Admin → Settings → LLM."
        abort "Error: No LLM model selected. Please check the logs."
      end
      logger.info "✓ LLM model is selected."

      if config.adapter == "openai-compatible" && config.api_key.blank?
        logger.warn "✗ Sensemaker requires an API key for provider '#{config.compat_provider}'. " \
                    "Set tenant secret llm.#{config.compat_provider}_api_key."
        abort "Error: Missing API key for selected provider. Please check the logs."
      end
      logger.info "✓ Provider credentials are configured."
    end

    def build_health_check_command_parts(config, output_file)
      parts = [
        "--output_file", output_file.to_s,
        "--adapter", config.adapter
      ]
      parts.concat(["--model_name", config.model]) if config.model.present?

      case config.adapter
      when "vertex"
        parts.concat(["--vertex_project", config.vertex_project_id])
        parts.concat(["--vertex_location", config.vertex_location])
      when "openai-compatible"
        parts.concat(["--provider", config.compat_provider])
        parts.concat(["--api_key", config.api_key]) if config.api_key.present?
        parts.concat(["--base_url", config.base_url]) if config.base_url.present?
      when "gemini"
        parts.concat(["--api_key", config.api_key]) if config.api_key.present?
      end

      parts
    end

    def redact_command_for_log(command)
      command.to_s.gsub(/--api_key\s+\S+/, "--api_key [REDACTED]")
    end

    def check_sensemaker_cli(logger)
      config = runtime_config

      output_file = "#{Sensemaker::Paths.sensemaker_data_folder}/verify-output-#{Time.current.to_i}.txt"
      cli = Sensemaker::Paths.sensemaking_cli(Sensemaker::HEALTH_CHECK_CLI)
      command_parts = build_health_check_command_parts(config, output_file)
      full_command = ([cli] + command_parts).map { |part| Shellwords.escape(part) }.join(" ")

      logger.info "Running command: #{redact_command_for_log(full_command)}"
      output = `#{full_command} 2>&1`
      result = $?.exitstatus

      if result.eql?(0)
        logger.info "✓ Sensemaker CLI is working correctly."
        logger.info output
      else
        logger.warn "✗ Sensemaker CLI is not working correctly."
        logger.warn output
        raise "Sensemaker CLI is not working correctly."
      end
    end

    def check_is_enabled(logger)
      setting = Setting.find_by(key: "feature.sensemaker")
      if setting.present?
        logger.info "✓ Sensemaker setting found"
      else
        logger.warn "✗ Sensemaker setting not found"
        raise "Sensemaker setting not found"
      end

      if Setting["feature.sensemaker"].present?
        logger.info "✓ Sensemaker is enabled via feature.sensemaker setting"
      else
        logger.warn "✗ Sensemaker is disabled via feature.sensemaker setting"
        raise "Sensemaker is disabled via feature.sensemaker setting"
      end
    end

    def check_package(logger)
      pip = Sensemaker::Paths.sensemaker_bin.join("pip")
      unless File.executable?(pip)
        logger.warn "✗ pip not found in Sensemaker venv: #{pip}"
        raise "Sensemaker Python venv is missing pip. Run: bundle exec rake sensemaker:setup"
      end

      show_output = `#{Shellwords.escape(pip.to_s)} show #{Sensemaker::PYTHON_PACKAGE} 2>&1`
      unless $?.success?
        logger.warn "✗ #{Sensemaker::PYTHON_PACKAGE} is not installed in the venv."
        logger.warn show_output
        raise "#{Sensemaker::PYTHON_PACKAGE} not installed. Run: bundle exec rake sensemaker:setup"
      end

      version_line = show_output.lines.find { |line| line.start_with?("Version:") }
      installed_version = version_line&.split(":", 2)&.last&.strip
      logger.info "✓ #{Sensemaker::PYTHON_PACKAGE} installed: #{installed_version}"

      if installed_version != Sensemaker::PYTHON_PACKAGE_VERSION
        logger.warn "Expected version #{Sensemaker::PYTHON_PACKAGE_VERSION}, found #{installed_version}."
        logger.warn "Run: bundle exec rake sensemaker:setup"
        raise "Sensemaker Python package version mismatch."
      end
    end

    def check_key_file(logger)
      adapter = runtime_config.adapter
      if adapter != "vertex" && adapter != "gemini"
        logger.info "Skipping GCP credentials file check (adapter is #{adapter || "not set"})."
        return
      end

      key_path = Rails.application.secrets.google_application_credentials
      if key_path.present?
        path = Pathname.new(key_path).absolute? ? key_path : Rails.root.join(key_path).to_s
        if File.exist?(path)
          logger.info "✓ Key file found: #{path}"
        else
          logger.warn "✗ Key file not found at path apis.google_application_credentials : #{path}"
          raise "Key file not found: #{path}"
        end
      else
        logger.info "✓ Using Application Default Credentials " \
                    "(gcloud auth application-default login or metadata server)."
      end
    end

    def check_directories(logger)
      venv_path = Sensemaker::Paths.sensemaker_venv
      bin_path = Sensemaker::Paths.sensemaker_bin
      cli_path = Sensemaker::Paths.sensemaker_bin.join(Sensemaker::HEALTH_CHECK_CLI)
      sensemaker_path = Sensemaker::Paths.sensemaker_folder
      data_path = Sensemaker::Paths.sensemaker_data_folder

      [
        [venv_path, "Sensemaker Python venv"],
        [bin_path, "Sensemaker venv bin directory"],
        [cli_path, "sensemaking-health-check CLI"],
        [sensemaker_path, "Sensemaker folder"],
        [data_path, "Sensemaker data folder"]
      ].each do |path, description|
        if File.exist?(path)
          logger.info "✓ #{description} found: #{path}"
        else
          logger.warn "✗ #{description} not found: #{path}"
          raise "#{description} not found: #{path}"
        end
      end

      logger.info "✓ Directories found."
    end

    def setup_for_tenant(logger)
      begin
        data_path = Sensemaker::Paths.sensemaker_data_folder
      rescue => e
        logger.warn "Could not get data path from Sensemaker::Paths: #{e.message}"
        logger.warn "Using default path instead"
        data_path = Rails.root.join("vendor/sensemaking-tools/data")
      end

      logger.info "Using data path: #{data_path}"
      setup_data_directory(data_path, logger)
      add_feature_flag(logger)

      logger.info "Sensemaker setup complete!"
      logger.info "Ensure tenant LLM settings are configured for the selected provider."
      logger.info "To verify your installation, run: bundle exec rake sensemaker:verify"
    end

    def check_dependencies(logger)
      logger.info "Checking environment dependencies..."
      check_dependency(logger, "python3", "Python 3")
      check_python_version(logger)
      check_dependency(logger, "pip3",
                       "pip") unless File.executable?(Sensemaker::Paths.sensemaker_bin.join("pip"))
      logger.info "All dependencies are available."
    end

    def check_python_version(logger)
      version_check = "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)"
      unless system("python3", "-c", version_check)
        logger.warn "Python 3.10 or newer is required for Sensemaker tools."
        raise "Python 3.10+ is required for Sensemaker tools."
      end
      logger.info "✓ Python version is 3.10 or newer: #{`python3 --version`.strip}"
    end

    def check_dependency(logger, cmd, display_name)
      unless system("which", cmd, out: File::NULL, err: File::NULL)
        logger.warn "#{display_name} not found. Please install #{display_name} to use the Sensemaker feature."
        raise "#{display_name} not found. Please install #{display_name} to use the Sensemaker feature."
      end
      logger.info "✓ #{display_name} found: #{`#{cmd} --version 2>&1 | head -1`.strip}"
    end

    def ensure_python_venv_and_package(logger)
      sensemaker_path = Sensemaker::Paths.sensemaker_folder
      venv_path = Sensemaker::Paths.sensemaker_venv
      pip_path = Sensemaker::Paths.sensemaker_bin.join("pip")

      FileUtils.mkdir_p(sensemaker_path)

      unless File.directory?(venv_path)
        logger.info "Creating Python virtual environment at #{venv_path}..."
        unless system("python3", "-m", "venv", venv_path.to_s)
          logger.warn "Failed to create Python venv at #{venv_path}"
          raise "Failed to create Python venv."
        end
        logger.info "✓ Virtual environment created."
      else
        logger.info "✓ Virtual environment already exists at #{venv_path}"
      end

      unless File.executable?(pip_path)
        logger.warn "✗ pip not found in venv after creation: #{pip_path}"
        raise "pip not found in Sensemaker venv."
      end

      package_spec = "#{Sensemaker::PYTHON_PACKAGE}==#{Sensemaker::PYTHON_PACKAGE_VERSION}"
      logger.info "Installing #{package_spec}..."

      upgrade_pip = `#{Shellwords.escape(pip_path.to_s)} install --upgrade pip 2>&1`
      unless $?.success?
        logger.warn "✗ Failed to upgrade pip in venv"
        logger.warn upgrade_pip
        raise "Failed to upgrade pip in Sensemaker venv."
      end

      install_output = `#{Shellwords.escape(pip_path.to_s)} install #{package_spec} 2>&1`
      unless $?.success?
        logger.warn "✗ Failed to install #{package_spec}"
        logger.warn install_output
        raise "Failed to install #{Sensemaker::PYTHON_PACKAGE}."
      end

      logger.info install_output
      Sensemaker::Paths.sensemaking_cli(Sensemaker::HEALTH_CHECK_CLI)
      logger.info "✓ #{Sensemaker::HEALTH_CHECK_CLI} is available."
    end

    def verify_python_cli_available(logger)
      cli = Sensemaker::Paths.sensemaking_cli(Sensemaker::HEALTH_CHECK_CLI)
      output = `#{Shellwords.escape(cli.to_s)} --help 2>&1`

      if $?.success?
        logger.info "Sensemaker CLI tool is working correctly."
      else
        logger.warn output
        logger.warn "Failed to run Sensemaker CLI tool. Please check the installation."
        raise "Failed to run Sensemaker CLI tool. Please check the installation."
      end
    end

    def setup_sensemaker_directory(sensemaker_path, logger)
      logger.info "Setting up sensemaking-tools directory..."
      FileUtils.mkdir_p(sensemaker_path) unless File.directory?(sensemaker_path)
      logger.info "Sensemaker directory ready."
    end

    def setup_data_directory(data_path, logger)
      logger.info "Setting up data directory..."
      FileUtils.mkdir_p(data_path) unless File.directory?(data_path)
      logger.info "Data directory created."
    end

    def add_feature_flag(logger)
      setting = Setting.find_or_initialize_by(key: "feature.sensemaker")
      if setting.new_record?
        logger.info "Adding sensemaker feature flag..."
        setting.value = "true"
        setting.save!
        logger.info "Feature flag added."
      else
        logger.info "Feature flag already exists, enabling sensemaker..."
        setting.update!(value: "true")
        logger.info "Sensemaker enabled using feature.sensemaker setting."
      end
    end

    def runtime_config
      @runtime_config ||= Sensemaker::RuntimeConfig.new(setting: Setting, llm_context: Llm::Config.context)
    end
end
