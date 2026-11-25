# frozen_string_literal: true

module SensemakerExt
  module BackendPatch
    def for(job, runtime_config:)
      return super unless SensemakerExt::Loader.enabled?

      script_backend = Sensemaker::ScriptRegistry.backend_for(job.script)
      if script_backend == :python
        return SensemakerExt::Backend::Python.new(job, runtime_config: runtime_config)
      end

      super
    end
  end
end
