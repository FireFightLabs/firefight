module Integrations
  # The code behind one provider of config/integration_providers.yml. Each provider that has code of its own declares it
  # in one file, app/services/integrations/providers/<key>.rb, naming its parts, and nothing else lists it. A provider
  # without such a file, such as Linear, is used through its own tools and has no parts.
  #
  # The parts, each optional, are named as class names so a definition loads nothing it does not use:
  #   pack             a NativePack subclass, for a provider with kind: native
  #   adapter          a Capabilities adapter, answering logs, metrics and the rest for what is on the map
  #   map_reader       a RemoteReader that puts what a remote server reaches on the map (a pack reads its own, map_of)
  #   baseline_reader  a RemoteReader that reads what normal looks like (a pack reads its own, baselines_of)
  #   health_probe     a RemoteReader that checks a remote server reaches the account behind it (a pack checks its own)
  #   source_links     a builder that links a remote server's result to the page it came from
  #   read_guard       a ReadGuards module, telling a read from a change for a tool that can make both
  # redacted_fields names answer fields that hold a credential, which never reach the model.
  class Provider
    PARTS = %i[pack adapter map_reader baseline_reader health_probe source_links read_guard].freeze
    KEY_FORMAT = /\A[a-z0-9_]+\z/

    attr_reader :key, :redacted_fields

    def initialize(key:, redacted_fields: [], **parts)
      unknown = parts.keys - PARTS
      raise ArgumentError, "#{key} names parts a provider does not have: #{unknown.join(', ')}" if unknown.any?

      @key = key
      @redacted_fields = redacted_fields.map(&:to_s).freeze
      @parts = parts.transform_values(&:to_s).freeze
    end

    PARTS.each do |part|
      define_method(part) { @parts[part]&.constantize }
    end

    # The class names this definition gives, so a test can load every one.
    def part_names = @parts

    # The provider's definition, or one with no parts for a provider that has no code of its own.
    def self.for(key)
      key = key.to_s
      name = key.camelize
      key.match?(KEY_FORMAT) && Providers.const_defined?(name, false) ? Providers.const_get(name, false) : new(key: key)
    end

    # Every provider in the registry, as its definition.
    def self.all = IntegrationProvider.all.map { |entry| self.for(entry.key) }
  end
end
