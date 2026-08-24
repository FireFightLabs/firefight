FirefightAi.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"] || Rails.application.credentials.dig(:openai, :api_key)
  # Workspace-wide model override. When unset, each feature keeps its own
  # default (postmortems use a stronger model than chat responses).
  config.default_model = ENV["FIREFIGHT_AI_MODEL"]
end
