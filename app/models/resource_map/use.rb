# A setting of a service that says where something it talks to is, such as DATABASE_URL on web. Only the setting's name
# is kept, with a keyed digest of the host and port it named (ResourceMap::Fingerprint), so the value, and the password
# a connection string holds, never leaves memory. A setting whose value the provider hides is kept by name alone, which
# is a clue rather than an address.
class ResourceMap::Use < ApplicationRecord
  self.table_name = "resource_map_uses"

  # The most settings kept for one resource, so a service with hundreds of variables cannot fill the table.
  LIMIT = 100
  # Names that say a setting is about where something is, the only ones kept when their value says nothing.
  CONNECTION_NAME = /(?:\A|_)(?:URLS?|URI|DSN|HOSTS?|HOSTNAME|ADDR|ADDRESS|ENDPOINT|SERVER|CONN|CONNECTION|CONNECTION_STRING)(?:\z|_)|
                     DATABASE|POSTGRES|\APG|MYSQL|MONGO|REDIS|VALKEY|MEMCACHE|AMQP|RABBIT|KAFKA|NATS|(?:\A|_)(?:DB|KV|SQL)(?:\z|_)/x
  # A host given on its own, with the setting beside it that holds its port, such as DB_HOST and DB_PORT or PGHOST and PGPORT.
  HOST_NAME = /\A(.*?)_?HOST(?:NAME)?\z/
  # The port a bare host is reached on, by what its setting is named for, when no setting beside it names one.
  PORT_BY_WORD = { "PG" => 5432, "POSTGRES" => 5432, "POSTGRESQL" => 5432, "MYSQL" => 3306, "REDIS" => 6379, "VALKEY" => 6379,
                   "MONGO" => 27_017, "MONGODB" => 27_017 }.freeze

  # What a sweep read, with nothing of the value but the digests, its scheme and its port.
  Found = Data.define(:from, :variable, :fingerprint, :domain_fingerprint, :scheme, :port, :database_fingerprint, :tenant_fingerprint) do
    def initialize(from:, variable:, fingerprint: nil, domain_fingerprint: nil, scheme: nil, port: nil, database_fingerprint: nil,
                   tenant_fingerprint: nil) = super

    def address? = fingerprint.present?
  end

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"
  belongs_to :integration_environment

  # The settings of the resource from, read from values (each setting's name and value, in memory only) and names (the
  # settings whose values the provider does not show). Nothing of a value is kept but what Found holds.
  def self.read(from:, workspace:, values: {}, names: [])
    values = values.to_h.transform_keys(&:to_s)
    found = values.filter_map { |variable, value| of(from, variable, value, workspace, values) }
    found += (names.map(&:to_s) - values.keys).uniq.filter_map { |variable| named(from, variable) }
    found.uniq(&:variable).first(LIMIT)
  end

  # One setting, or nil for one that names nothing Firefight can use. scheme is what the provider says the value is
  # for, such as an app setting a cloud labels PostgreSQL.
  def self.of(from, variable, value, workspace, siblings = {}, scheme: nil)
    parsed = ResourceMap::ConnectionString.parse(value, scheme: scheme) || bare_host(variable, value, siblings)
    return named(from, variable) unless parsed

    Found.new(from: from, variable: variable.to_s, fingerprint: ResourceMap::Fingerprint.of(parsed.host, parsed.port, workspace),
              domain_fingerprint: ResourceMap::Fingerprint.of_domain(parsed.host, parsed.port, workspace), scheme: parsed.scheme,
              port: parsed.port, database_fingerprint: ResourceMap::Fingerprint.of_name(parsed.database, workspace),
              tenant_fingerprint: ResourceMap::Fingerprint.of_name(tenant_of(parsed.user), workspace))
  end

  # A setting that names something exactly rather than an address, such as the ARN of the secret a value is read from.
  def self.reference(from:, variable:, reference:, workspace:)
    fingerprint = ResourceMap::Fingerprint.of_reference(reference, workspace)
    fingerprint && Found.new(from: from, variable: variable.to_s, fingerprint: fingerprint)
  end

  # A shared host tells its tenants apart by a suffix on the user's name, role.tenant, which a pooler may follow with
  # its own options after a bar.
  def self.tenant_of(user)
    name = user.to_s.split("|").first.to_s
    name.include?(".") ? name.split(".").last : nil
  end

  # A setting known by its name only. Kept when the name says where something is or names a store's provider.
  def self.named(from, variable)
    name = variable.to_s.upcase
    return unless name.match?(CONNECTION_NAME) || IntegrationProvider.setting_words.any? { |word| words(name).include?(word) }

    Found.new(from: from, variable: variable.to_s)
  end

  def self.words(name) = name.to_s.upcase.split(/[^A-Z0-9]+/).reject(&:empty?)

  # DB_HOST=db.internal with DB_PORT beside it, read as the address they name together.
  def self.bare_host(variable, value, siblings)
    prefix = variable.to_s.upcase[HOST_NAME, 1]
    host = value.to_s.strip
    return if prefix.nil? || host.empty? || host.match?(%r{[\s/=@;]})

    host, port = host.split(":", 2) if host.count(":") == 1
    port ||= siblings.find { |name, _| name.to_s.upcase.delete("_") == "#{prefix.delete('_')}PORT" }&.last
    port ||= words(prefix).filter_map { |word| PORT_BY_WORD[word] }.first
    return unless port.to_s.match?(/\A\d+\z/)

    database = siblings.find { |name, _| %W[#{prefix}DATABASE #{prefix}NAME #{prefix}DB].include?(name.to_s.upcase.delete("_")) }&.last
    ResourceMap::ConnectionString::Parsed.new(scheme: nil, host: host, port: port.to_i, database: database, user: nil)
  end
  private_class_method :bare_host
end
