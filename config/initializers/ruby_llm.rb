RubyLLM.configure do |config|
  config.anthropic_api_key = Rails.application.credentials.dig(:anthropic, :api_key)
end
