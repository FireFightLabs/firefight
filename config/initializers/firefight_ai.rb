FirefightAi.configure do |config|
  config.provider_settings = FirefightAi::Configuration::PROVIDER_SETTINGS.index_with do |setting|
    ENV[setting.to_s.upcase].presence
  end.compact
  config.openai_api_key ||= Rails.application.credentials.dig(:openai, :api_key)
  config.openrouter_management_key = ENV["OPENROUTER_MANAGEMENT_KEY"].presence

  config.default_model = ENV["FIREFIGHT_AI_MODEL"]
  config.default_provider = ENV["FIREFIGHT_AI_PROVIDER"]
  config.quick_model = ENV["FIREFIGHT_AI_QUICK_MODEL"].presence
  config.quick_provider = ENV["FIREFIGHT_AI_QUICK_PROVIDER"].presence
  config.backup_model = ENV["FIREFIGHT_AI_BACKUP_MODEL"].presence
  config.backup_provider = ENV["FIREFIGHT_AI_BACKUP_PROVIDER"].presence

  # Unset means on. Only an explicit false, 0 or off turns milestones off for every workspace.
  config.milestones_enabled = ENV["AI_MILESTONES_ENABLED"].blank? ||
    ActiveModel::Type::Boolean.new.cast(ENV["AI_MILESTONES_ENABLED"])

  config.on_refused = ->(payer, provider, error) { AiRefusal.record!(payer, provider, error) }
  config.playbooks = -> { Chat::Skill.playbooks_text }

  # net_http_persistent unless a process says otherwise, such as a worker running its jobs on fibers with async_http.
  config.http_adapter = ENV["FIREFIGHT_AI_HTTP_ADAPTER"]
  # On unless an explicit false, 0 or off, as for a bench run comparing tool search with opening groups.
  config.tool_search = ENV["FIREFIGHT_AI_TOOL_SEARCH"].blank? || ActiveModel::Type::Boolean.new.cast(ENV["FIREFIGHT_AI_TOOL_SEARCH"])
  # Tokens of tool definitions held whole from the start where the provider does not search tools, blank for the default.
  config.held_tools_budget = ENV["FIREFIGHT_AI_HELD_TOOLS_BUDGET"]
  # Off unless set, and exported only where OTEL_EXPORTER_OTLP_ENDPOINT starts the OpenTelemetry SDK.
  config.trace_calls = ActiveModel::Type::Boolean.new.cast(ENV["FIREFIGHT_AI_TRACING"]) == true
  config.judgments = ENV["FIREFIGHT_AI_JUDGMENTS"]
  # auto (the default) hands a chat's reads of connected systems to specialists when its tools do not fit the held tools
  # budget, and on or off overrides that, for the bench.
  config.specialists = ENV["FIREFIGHT_AI_SPECIALISTS"]
  # quick (the default) or main, the model a specialist runs on.
  config.specialist_model = ENV["FIREFIGHT_AI_SPECIALIST_MODEL"]
end

# A workspace's AI account with its own API base calls through this adapter where private networks are refused.
Faraday::Adapter.register_middleware(firefight_public_address: -> { Integrations::PublicAddressAdapter })
