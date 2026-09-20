# Prices and new models arrive only when the registry is refreshed, and a stale price makes every spend cap wrong.
class RefreshModelRegistryJob < ApplicationJob
  queue_as :background

  def perform
    known = FirefightAi.refresh_models!
    Rails.logger.info({ event: "ai.model_registry_refreshed", models: known }.to_json)

    unpriced = configured_models.reject { |model| FirefightAi.priced?(model) }
    return if unpriced.empty?

    Rails.logger.warn({ event: "ai.models_without_pricing", models: unpriced }.to_json)
  end

  private

  # What this deployment would actually run, since a price nobody uses is nobody's problem.
  def configured_models
    purposes = AiPurpose::ALL + [ AiPurpose::EMBEDDING ]
    deployment = purposes.map { |purpose| FirefightAi.model_for(purpose).model }
    (deployment + AiModelOverride.distinct.pluck(:model)).compact.uniq
  end
end
