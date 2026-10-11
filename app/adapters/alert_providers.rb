module AlertProviders
  # In the order the settings screen offers them, the generic webhook first and the rest by label.
  ADAPTERS = {
    AlertSource::PROVIDER_GENERIC => "AlertProviders::Generic",
    AlertSource::PROVIDER_AXIOM => "AlertProviders::Axiom",
    AlertSource::PROVIDER_BETTER_STACK => "AlertProviders::BetterStack",
    AlertSource::PROVIDER_DATADOG => "AlertProviders::Datadog",
    AlertSource::PROVIDER_GRAFANA => "AlertProviders::Grafana",
    AlertSource::PROVIDER_HONEYBADGER => "AlertProviders::Honeybadger",
    AlertSource::PROVIDER_HONEYCOMB => "AlertProviders::Honeycomb",
    AlertSource::PROVIDER_MIXPANEL => "AlertProviders::Mixpanel",
    AlertSource::PROVIDER_NEW_RELIC => "AlertProviders::NewRelic",
    AlertSource::PROVIDER_NORTHFLANK => "AlertProviders::Northflank",
    AlertSource::PROVIDER_OPENSTATUS => "AlertProviders::Openstatus",
    AlertSource::PROVIDER_OPSGENIE => "AlertProviders::Opsgenie",
    AlertSource::PROVIDER_PAGERDUTY => "AlertProviders::Pagerduty",
    AlertSource::PROVIDER_POSTHOG => "AlertProviders::Posthog",
    AlertSource::PROVIDER_ALERTMANAGER => "AlertProviders::Alertmanager",
    AlertSource::PROVIDER_SENTRY => "AlertProviders::Sentry",
    AlertSource::PROVIDER_SIGNOZ => "AlertProviders::Signoz"
  }.freeze

  def self.for(provider)
    class_name = ADAPTERS.fetch(provider) do
      raise ArgumentError, "unknown alert provider: #{provider.inspect}"
    end
    class_name.constantize
  end

  # Every provider a source can be made for, with how it is pointed at a source in the provider's own words.
  def self.catalog
    ADAPTERS.map { |provider, class_name| class_name.constantize.descriptor(provider) }
  end
end
