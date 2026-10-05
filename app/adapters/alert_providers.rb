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
end
