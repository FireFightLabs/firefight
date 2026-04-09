FirefightAi.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] || Rails.application.credentials.dig(:anthropic, :api_key)
  config.default_model = ENV.fetch("FIREFIGHT_AI_MODEL", "claude-sonnet-4-6")
end
