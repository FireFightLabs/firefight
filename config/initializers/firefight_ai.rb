FirefightAi.configure do |config|
  # One env var per RubyLLM provider setting, named after it: OPENAI_API_KEY,
  # ANTHROPIC_API_KEY, GEMINI_API_KEY, BEDROCK_REGION, OLLAMA_API_BASE, ...
  config.provider_settings = FirefightAi::Configuration::PROVIDER_SETTINGS.index_with do |setting|
    ENV[setting.to_s.upcase].presence
  end.compact
  config.openai_api_key ||= Rails.application.credentials.dig(:openai, :api_key)

  # Deployment-wide model, below each purpose's own env var and above the
  # built-in fallbacks. FIREFIGHT_AI_PROVIDER names the provider for a model
  # the registry does not know.
  config.default_model = ENV["FIREFIGHT_AI_MODEL"]
  config.default_provider = ENV["FIREFIGHT_AI_PROVIDER"]
end
