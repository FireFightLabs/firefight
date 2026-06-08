FirefightAi.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key)
  config.default_model  = ENV.fetch("FIREFIGHT_AI_MODEL", "gpt-4o-mini")
end
