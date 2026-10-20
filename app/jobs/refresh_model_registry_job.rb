# Prices and new models arrive only when the registry is refreshed, and a stale price makes every spend cap wrong.
class RefreshModelRegistryJob < ApplicationJob
  queue_as :background

  # How long before a provider's off-peak dates run out the job starts asking for the next year's.
  PEAK_DATES_NOTICE = 45.days

  def perform
    known = FirefightAi.refresh_models!
    Rails.logger.info({ event: "ai.model_registry_refreshed", models: known }.to_json)

    warn_about_unpriced
    warn_about_unknown_windows
    warn_about_ending_peak_dates
  end

  private

  def warn_about_unpriced
    unpriced = configured_models.reject { |model| FirefightAi.priced?(model) }
    Rails.logger.warn({ event: "ai.models_without_pricing", models: unpriced }.to_json) if unpriced.any?
  end

  # The agent does not run on a model whose window is not known, so this is what to fix when it will not start.
  def warn_about_unknown_windows
    unknown = agent_models.reject { |model, provider| FirefightAi.context_window(model, provider: provider) }.map(&:first)
    Rails.logger.warn({ event: "ai.models_without_context_window", models: unknown }.to_json) if unknown.any?
  end

  # A provider's off-peak dates are published a year at a time, so this asks for next year's while there is time to add
  # them, and every day after the list ran out.
  def warn_about_ending_peak_dates
    ending = AiProviders.all.filter_map do |provider|
      through = provider.peak_pricing&.dates_known_through
      { provider: provider.slug, known_through: through.iso8601 } if through && Date.current > through - PEAK_DATES_NOTICE
    end
    Rails.logger.warn({ event: "ai.peak_pricing_dates_ending", providers: ending }.to_json) if ending.any?
  end

  # Each with the provider it runs on, when one is named, since one id can be several providers' with different sizes.
  def agent_models
    deployment = FirefightAi.model_for(AiPurpose::INVESTIGATION)
    overrides = AiModelOverride.for_purpose(AiPurpose::INVESTIGATION).distinct.pluck(:model, :provider)
    ([ [ deployment.model, deployment.provider.presence ] ] + overrides.map { |model, provider| [ model, provider.presence ] })
      .reject { |model, _| model.blank? }.uniq
  end

  # What this deployment would actually run, since a price nobody uses is nobody's problem.
  def configured_models
    purposes = AiPurpose::ALL + [ AiPurpose::EMBEDDING ]
    deployment = purposes.map { |purpose| FirefightAi.model_for(purpose).model }
    (deployment + AiModelOverride.distinct.pluck(:model)).compact.uniq
  end
end
