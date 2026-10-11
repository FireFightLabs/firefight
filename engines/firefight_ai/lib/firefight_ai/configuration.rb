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

    # The Faraday adapter every model call goes through. net_http_persistent keeps connections to a provider open between
    # calls, for threaded workers and the web. async_http does the same for a process that runs its jobs on fibers.
    # net_http opens one per call, as RubyLLM does on its own.
    HTTP_ADAPTERS = %i[net_http net_http_persistent async_http].freeze
    DEFAULT_HTTP_ADAPTER = :net_http_persistent
    attr_reader :http_adapter

    # Whether a provider that searches tools itself is handed the long tail deferred (FirefightAi.tool_search?). On unless
    # turned off, which a bench run comparing the two ways does, or a deployment whose provider's search misbehaves.
    attr_accessor :tool_search

    # Where the provider does not search tools itself, the tools whoever acts may call are all held from the start when
    # their definitions come to no more than this many tokens (FirefightAi.fits_up_front?). A chat that opens groups
    # changes its tool list each time, and since the tools come first in what a provider caches, every change writes
    # the whole cached front again, which on the bench was about two thirds of what a chat cost. Holding them all writes
    # them once. Past this, holding them costs more than the rewrites it saves, at about eleven calls and three group
    # openings a chat, so the chat opens groups instead.
    DEFAULT_HELD_TOOLS_BUDGET = 25_000
    attr_reader :held_tools_budget

    # Each model call, tool call and judgment as an OpenTelemetry span (RubyLLM::OpenTelemetry), sent wherever the
    # deployment's OpenTelemetry SDK exports. Spans carry the model, the provider, token counts and timings, never what
    # was said, and never a key.
    attr_accessor :trace_calls

    # How Halon makes its small yes or no decisions, such as whether a watched run is done or a cited step shows a claim.
    # structured asks the quick model for a structured answer. judge asks RubyLLM::Judge, on a model that answers
    # judgments, and falls back to structured on any other (FirefightAi::Judging).
    JUDGMENT_STRUCTURED = :structured
    JUDGMENT_JUDGE = :judge
    JUDGMENT_MODES = [ JUDGMENT_STRUCTURED, JUDGMENT_JUDGE ].freeze
    attr_reader :judgments

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

    # Returns the playbooks' words, which the version of every prompt carrying the manual includes (Manual.version).
    attr_accessor :playbooks

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
      @http_adapter = DEFAULT_HTTP_ADAPTER
      @tool_search = true
      @held_tools_budget = DEFAULT_HELD_TOOLS_BUDGET
      @trace_calls = false
      @judgments = JUDGMENT_STRUCTURED
    end

    # Blank keeps the default. Anything not in the list is refused at boot, so a typo never reaches a call.
    def http_adapter=(value)
      adapter = value.presence&.to_sym || DEFAULT_HTTP_ADAPTER
      raise ArgumentError, "FIREFIGHT_AI_HTTP_ADAPTER must be one of #{HTTP_ADAPTERS.join(', ')}, not #{value}" unless HTTP_ADAPTERS.include?(adapter)

      @http_adapter = adapter
    end

    # Blank keeps the default. Zero holds nothing up front, so every chat opens groups.
    def held_tools_budget=(value)
      budget = value.blank? ? DEFAULT_HELD_TOOLS_BUDGET : Integer(value.to_s, exception: false)
      raise ArgumentError, "FIREFIGHT_AI_HELD_TOOLS_BUDGET must be a whole number of tokens, not #{value}" if budget.nil? || budget.negative?

      @held_tools_budget = budget
    end

    def judgments=(value)
      mode = value.presence&.to_sym || JUDGMENT_STRUCTURED
      raise ArgumentError, "FIREFIGHT_AI_JUDGMENTS must be one of #{JUDGMENT_MODES.join(', ')}, not #{value}" unless JUDGMENT_MODES.include?(mode)

      @judgments = mode
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
