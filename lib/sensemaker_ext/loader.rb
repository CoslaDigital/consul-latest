# frozen_string_literal: true

require Rails.root.join("app/lib/sensemaker")
require Rails.root.join("app/lib/sensemaker/script_registry")
require Rails.root.join("app/lib/sensemaker/backend")
require Rails.root.join("lib/sensemaker_ext/paths")
require Rails.root.join("lib/sensemaker_ext/backend/python")
require Rails.root.join("lib/sensemaker_ext/script_registry_patch")
require Rails.root.join("lib/sensemaker_ext/backend_patch")

module SensemakerExt
  module Loader
    module_function

    def enabled?
      @enabled == true
    end

    def install!
      return if @installed

      Sensemaker::ScriptRegistry.singleton_class.prepend(SensemakerExt::ScriptRegistryPatch)
      Sensemaker::Backend.singleton_class.prepend(SensemakerExt::BackendPatch)
      @enabled = true
      @installed = true
    end
  end
end
