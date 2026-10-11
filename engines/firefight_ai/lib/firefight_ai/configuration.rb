module FirefightAi
  class Configuration
    # Filled by the initializer from env vars of the same name upcased, handed to RubyLLM as is.
    PROVIDER_SETTINGS = %i[
      openai_api_key openai_api_base openai_organization_id openai_project_id
      anthropic_api_key anthropic_api_base
      gemini_api_key gemini_api_base
      vertexai_service_account_key vertexai_project_id vertexai_location vertexai_api_base
      bedrock_api_key bedrock_secret_key bedrock_session_token bedrock_region bedrock_api_base
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

    # The deployment's quick model for side jobs (summaries, milestones, mention replies, judging a watch or a memory),
    # when no purpose names its own. Unset, side jobs run on the quick model the main model's provider recommends.
    attr_accessor :quick_model, :quick_provider

    # What Halon's own loop carries on with when the main model's provider stops answering, after the workspace's own
    # accounts on other providers. Unset, the backup model of each provider this deployment holds a key for
    # (AiProviders.deployment_backup_choices).
    attr_accessor :backup_model, :backup_provider

    # A read-only OpenRouter management key, used only to read the account's balance and never to call a model.
    attr_accessor :openrouter_management_key

    # Called with the payer, the provider and the error when a call is refused for good. The app sets the payer aside
    # and tells whoever can fix it, so the engine never writes that state or enqueues anything itself.
    attr_accessor :on_refused

    # Deploy-level kill switch for milestone noting. Entitlement and credits still gate per workspace.
    attr_writer :milestones_enabled

    def initialize
      @default_model = nil
      @default_provider = nil
      @quick_model = nil
      @quick_provider = nil
      @backup_model = nil
      @backup_provider = nil
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
