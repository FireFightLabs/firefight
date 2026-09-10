module AlertProviders
  ADAPTERS = {
    AlertSource::PROVIDER_GENERIC => "AlertProviders::Generic",
    AlertSource::PROVIDER_NORTHFLANK => "AlertProviders::Northflank"
  }.freeze

  def self.for(provider)
    class_name = ADAPTERS.fetch(provider) do
      raise ArgumentError, "unknown alert provider: #{provider.inspect}"
    end
    class_name.constantize
  end
end
