module AlertProviders
  ADAPTERS = {
    AlertSource::PROVIDER_GENERIC => "AlertProviders::Generic",
    AlertSource::PROVIDER_NORTHFLANK => "AlertProviders::Northflank",
    AlertSource::PROVIDER_PAGERDUTY => "AlertProviders::Pagerduty",
    AlertSource::PROVIDER_OPSGENIE => "AlertProviders::Opsgenie"
  }.freeze

  def self.for(provider)
    class_name = ADAPTERS.fetch(provider) do
      raise ArgumentError, "unknown alert provider: #{provider.inspect}"
    end
    class_name.constantize
  end

  # How a source is pointed at its URL, by provider, in the provider's own words. Settings shows it beside the URL.
  def self.setup_instructions
    ADAPTERS.to_h { |provider, class_name| [ provider, class_name.constantize::SETUP_INSTRUCTIONS ] }
  end
end
