FirefightAi.configure do |config|
  config.provider_settings = FirefightAi::Configuration::PROVIDER_SETTINGS.index_with do |setting|
    ENV[setting.to_s.upcase].presence
  end.compact
  config.openai_api_key ||= Rails.application.credentials.dig(:openai, :api_key)

  config.default_model = ENV["FIREFIGHT_AI_MODEL"]
  config.default_provider = ENV["FIREFIGHT_AI_PROVIDER"]
end
