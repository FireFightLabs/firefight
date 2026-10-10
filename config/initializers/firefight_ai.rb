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
end

# A workspace's AI account with its own API base calls through this adapter where private networks are refused.
Faraday::Adapter.register_middleware(firefight_public_address: -> { Integrations::PublicAddressAdapter })
