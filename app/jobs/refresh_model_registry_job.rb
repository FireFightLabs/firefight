# Prices and new models arrive only when the registry is refreshed, and a stale price makes every spend cap wrong.
class RefreshModelRegistryJob < ApplicationJob
  queue_as :background

  def perform
    known = FirefightAi.refresh_models!
    Rails.logger.info({ event: "ai.model_registry_refreshed", models: known }.to_json)

    warn_about_unpriced
    warn_about_unknown_windows
  end

  private

  def warn_about_unpriced
    unpriced = configured_models.reject { |model| FirefightAi.priced?(model) }
    Rails.logger.warn({ event: "ai.models_without_pricing", models: unpriced }.to_json) if unpriced.any?
  end

  # The agent does not run on a model whose window is not known, so this is what to fix when it will not start.
  def warn_about_unknown_windows
    unknown = agent_models.reject { |model| FirefightAi.context_window(model) }
    Rails.logger.warn({ event: "ai.models_without_context_window", models: unknown }.to_json) if unknown.any?
  end

  def agent_models
    deployment = FirefightAi.model_for(AiPurpose::INVESTIGATION).model
    overrides = AiModelOverride.for_purpose(AiPurpose::INVESTIGATION).distinct.pluck(:model)
    ([ deployment ] + overrides).compact.uniq
  end

  # What this deployment would actually run, since a price nobody uses is nobody's problem.
  def configured_models
    purposes = AiPurpose::ALL + [ AiPurpose::EMBEDDING ]
    deployment = purposes.map { |purpose| FirefightAi.model_for(purpose).model }
    (deployment + AiModelOverride.distinct.pluck(:model)).compact.uniq
  end
end
