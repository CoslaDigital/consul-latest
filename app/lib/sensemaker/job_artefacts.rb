module Sensemaker
  class JobArtefacts
    attr_reader :job

    DEFAULT_OUTPUT_BASENAME = ->(_job) { "output.csv" }
    DEFAULT_INPUT_PATH = ->(job) { File.join(Sensemaker::Paths.job_directory(job), "input.csv") }

    def initialize(job)
      @job = job
    end

    def job_directory
      Sensemaker::Paths.job_directory(job)
    end

    def relative_job_directory
      Sensemaker::Paths.relative_job_directory(job)
    end

    def ensure_directory!
      FileUtils.mkdir_p(job_directory)
    end

    def output_file_name
      config[:output_basename].call(job)
    end

    def multiple_outputs?
      config[:output_suffixes].any?
    end

    def default_output_path
      File.join(job_directory, output_file_name)
    end

    def relative_output_path
      File.join(relative_job_directory, output_file_name)
    end

    def persisted_output_path
      path = job.read_attribute(:persisted_output)
      return nil if path.blank?

      Rails.root.join(path)
    end

    def output_artefact_paths
      base_path = if job.persisted_output.present?
                    persisted_output_path.to_s
                  else
                    default_output_path
                  end

      suffixes = config[:output_suffixes]
      suffixes.empty? ? [base_path] : suffixes.map { |suffix| "#{base_path}#{suffix}" }
    end

    def existing_output_artefact_paths
      output_artefact_paths.select { |path| File.exist?(path) }
    end

    def input_path
      stored = job.read_attribute(:input_file)
      return stored if stored.present?

      default = config[:default_input_path]
      default&.call(job)
    end

    def input_artefact_paths
      base_path = input_path.to_s
      return [] if base_path.blank?

      input_suffixes = config[:input_suffixes]
      input_suffixes.empty? ? [base_path] : input_suffixes.map { |suffix| "#{base_path}#{suffix}" }
    end

    def additional_input_artefact_paths
      Array(config[:additional_input_scripts]).flat_map do |script|
        preparation_outputs_for(script)
      end
    end

    def existing_input_artefact_paths
      existing_direct_input_artefact_paths = input_artefact_paths.select { |path| File.exist?(path) }
      (existing_direct_input_artefact_paths + additional_input_artefact_paths).uniq
    end

    def existing_preparation_output_artefact_paths
      preparation_output_paths_by_script.values.flatten
    end

    def report_config_path
      File.join(job_directory, "config.json")
    end

    def write_report_config(config)
      ensure_directory!
      File.write(report_config_path, JSON.pretty_generate(config))
      report_config_path
    end

    def complete?
      output_artefact_paths.all? { |path| File.exist?(path) }
    end

    def preparation_jobs
      jobs = []
      queue = job.children.order(:id).to_a
      while (child = queue.shift)
        jobs << child
        queue.concat(child.children.order(:id).to_a)
      end
      jobs
    end

    # When multiple prep jobs share a script, prefer the latest by id that has
    # at least one existing output file.
    def preparation_output_paths_by_script
      result = {}
      preparation_jobs.group_by(&:script).each do |script, jobs|
        preferred = jobs.sort_by(&:id).reverse.find do |prep_job|
          prep_job.artefacts.existing_output_artefact_paths.any?
        end
        next if preferred.nil?

        result[script] = preferred.artefacts.existing_output_artefact_paths
      end
      result
    end

    def preparation_outputs_for(script)
      preparation_output_paths_by_script[script.to_s] || []
    end

    def preparation_output_for(script)
      preparation_outputs_for(script).first
    end

    def cleanup
      result = []
      result.concat(cleanup_job_directory)
      result.concat(cleanup_persisted_output)
      result.flatten!
      result.compact!
      result
    rescue StandardError
      nil
    end

    private

      def config
        Sensemaker::ScriptRegistry.artefact_config(job.script) || default_config
      end

      def default_config
        {
          output_basename: DEFAULT_OUTPUT_BASENAME,
          output_suffixes: [],
          default_input_path: DEFAULT_INPUT_PATH,
          input_suffixes: [],
          additional_input_scripts: []
        }
      end

      def cleanup_job_directory
        return [] unless Dir.exist?(job_directory)

        [FileUtils.rm_rf(job_directory)]
      end

      def cleanup_persisted_output
        path = persisted_output_path
        return [] unless path.present? && File.exist?(path)

        job_dir = File.expand_path(job_directory)
        persisted = File.expand_path(path.to_s)
        return [] if persisted == job_dir || persisted.start_with?("#{job_dir}/")

        [FileUtils.rm_f(path)]
      end
  end
end
