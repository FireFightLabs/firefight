# Prices and new models arrive only when the registry is refreshed, and a stale price makes every spend cap wrong.
class RefreshModelRegistryJob < ApplicationJob
  queue_as :background

  def perform
    Rails.logger.info({ event: "ai.model_registry_refreshed", models: FirefightAi.refresh_models! }.to_json)
  end
end
