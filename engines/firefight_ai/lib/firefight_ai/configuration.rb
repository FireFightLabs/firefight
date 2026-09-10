module FirefightAi
  class Configuration
    # Filled by the initializer from env vars of the same name upcased, handed to RubyLLM as is.
    PROVIDER_SETTINGS = %i[
      openai_api_key openai_api_base openai_organization_id openai_project_id
      anthropic_api_key anthropic_api_base
      gemini_api_key gemini_api_base
      vertexai_service_account_key vertexai_location vertexai_api_base
      bedrock_region bedrock_api_base
      azure_api_key azure_api_base azure_ai_auth_token
      deepseek_api_key deepseek_api_base
      mistral_api_key mistral_api_base
      perplexity_api_key perplexity_api_base
      openrouter_api_key openrouter_api_base
      ollama_api_key ollama_api_base
      gpustack_api_key gpustack_api_base
      xai_api_key xai_api_base
    ].freeze

    attr_accessor :default_model, :default_provider, :provider_settings, :request_timeout

    # Deploy-level kill switch for milestone noting. Entitlement and credits still gate per workspace.
    attr_writer :milestones_enabled

    def initialize
      @default_model = nil
      @default_provider = nil
      @provider_settings = {}
      @request_timeout = 120
      @milestones_enabled = true
    end

    def milestones_enabled?
      @milestones_enabled
    end

    def openai_api_key
      provider_settings[:openai_api_key]
    end

    def openai_api_key=(value)
      provider_settings[:openai_api_key] = value
    end
  end
end
