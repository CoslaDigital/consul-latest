require "rails_helper"

describe Sensemaker::RuntimeConfig do
  include_context "sensemaker llm config"

  let(:setting) { class_double(Setting) }
  let(:runtime_config) { Sensemaker::RuntimeConfig.new(setting: setting, llm_context: llm_context) }

  before do
    allow(setting).to receive(:[]).and_return(nil)
  end

  describe "#provider and #model" do
    it "normalizes provider and returns selected model" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return(" OpenAI ")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gpt-4.1-mini")

      expect(runtime_config.provider).to eq("openai")
      expect(runtime_config.model).to eq("gpt-4.1-mini")
    end
  end

  describe "#model_for" do
    before do
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-pro")
    end

    it "returns the primary model for :primary" do
      expect(runtime_config.model_for(:primary)).to eq("gemini-2.5-pro")
    end

    it "returns the fast model when set" do
      allow(setting).to receive(:[]).with("llm.sensemaker_fast_model")
        .and_return("gemini-2.5-flash-lite")

      expect(runtime_config.model_for(:fast)).to eq("gemini-2.5-flash-lite")
    end

    it "falls back to the primary model when fast is blank" do
      allow(setting).to receive(:[]).with("llm.sensemaker_fast_model").and_return(nil)

      expect(runtime_config.model_for(:fast)).to eq("gemini-2.5-pro")
    end

    it "raises for an unknown role" do
      expect { runtime_config.model_for(:unknown) }
        .to raise_error(ArgumentError, /Unknown Sensemaker model role/)
    end
  end

  describe "#adapter" do
    it "maps vertex provider to vertex adapter" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("VertexAI")
      expect(runtime_config.adapter).to eq("vertex")
    end

    it "maps openai provider to openai-compatible adapter" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("OpenAI")
      expect(runtime_config.adapter).to eq("openai-compatible")
    end

    it "maps gemini provider to gemini adapter" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Gemini")
      expect(runtime_config.adapter).to eq("gemini")
    end

    it "maps ollama provider to ollama adapter" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("ollama")
      expect(runtime_config.adapter).to eq("ollama")
    end

    it "returns nil for unsupported provider" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("unsupported")
      expect(runtime_config.adapter).to be(nil)
      expect(runtime_config.supported?).to be(false)
    end
  end

  describe "#compat_provider, #api_key and #base_url" do
    it "resolves openai-compatible provider settings" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("OpenAI")

      expect(runtime_config.compat_provider).to eq("openai")
      expect(runtime_config.api_key).to eq("openai-secret")
      expect(runtime_config.base_url).to eq("https://openai-proxy.example.com/v1")
    end

    it "resolves openrouter provider settings" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("OpenRouter")

      expect(runtime_config.adapter).to eq("openai-compatible")
      expect(runtime_config.compat_provider).to eq("openrouter")
      expect(runtime_config.api_key).to eq("openrouter-secret")
      expect(runtime_config.base_url).to eq("https://openrouter.ai/api/v1")
    end

    it "resolves gemini provider api key" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Gemini")

      expect(runtime_config.adapter).to eq("gemini")
      expect(runtime_config.compat_provider).to be(nil)
      expect(runtime_config.api_key).to eq("gemini-secret")
      expect(runtime_config.base_url).to be(nil)
    end

    it "resolves ollama base url" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("ollama")

      expect(runtime_config.compat_provider).to be(nil)
      expect(runtime_config.api_key).to be(nil)
      expect(runtime_config.base_url).to eq("http://localhost:11434")
    end

    it "returns nil api_key/base_url when config methods are unavailable" do
      limited_config = double("LLM config", vertexai_project_id: "proj", vertexai_location: nil)
      limited_context = double("LLM context", config: limited_config)
      cfg = Sensemaker::RuntimeConfig.new(setting: setting, llm_context: limited_context)
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("OpenAI")

      expect(cfg.api_key).to be(nil)
      expect(cfg.base_url).to be(nil)
    end
  end

  describe "#validation_error" do
    it "returns nil when configuration is valid (VertexAI)" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("VertexAI")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-flash-lite")

      expect(runtime_config.validation_error).to be(nil)
    end

    it "returns nil when configuration is valid (OpenAI)" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("OpenAI")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gpt-4o")

      expect(runtime_config.validation_error).to be(nil)
    end

    it "returns error when adapter is unsupported" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Unsupported")

      expect(runtime_config.validation_error).to include("Sensemaker LLM provider is not supported")
    end

    it "returns error when Vertex AI project_id is blank" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("VertexAI")
      allow(llm_config).to receive(:vertexai_project_id).and_return(nil)

      expect(runtime_config.validation_error).to include("Vertex AI is not configured")
    end

    it "returns error when model is blank" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("VertexAI")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return(nil)

      expect(runtime_config.validation_error).to include("Sensemaker requires an LLM model")
    end

    it "returns error when OpenAI-compatible provider has no API key" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("OpenAI")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gpt-4o")
      allow(llm_config).to receive(:openai_api_key).and_return(nil)

      expect(runtime_config.validation_error)
        .to include("Sensemaker requires an API key for provider 'openai'")
    end

    it "returns nil when configuration is valid (Gemini)" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Gemini")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-flash")

      expect(runtime_config.validation_error).to be(nil)
    end

    it "returns error when Gemini has no API key" do
      allow(setting).to receive(:[]).with("llm.sensemaker_provider").and_return("Gemini")
      allow(setting).to receive(:[]).with("llm.sensemaker_model").and_return("gemini-2.5-flash")
      allow(llm_config).to receive(:gemini_api_key).and_return(nil)

      expect(runtime_config.validation_error).to include("Sensemaker requires a Gemini API key")
    end
  end

  describe "#vertex_project_id and #vertex_location" do
    it "returns vertex project and location" do
      expect(runtime_config.vertex_project_id).to eq("sensemaker-466109")
      expect(runtime_config.vertex_location).to eq("global")
    end

    it "defaults vertex location to global when blank" do
      allow(llm_config).to receive(:vertexai_location).and_return(nil)
      expect(runtime_config.vertex_location).to eq("global")
    end
  end
end
