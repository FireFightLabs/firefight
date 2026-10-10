# How one repository is set up before its tests, as its CI sets it up: the services it starts, the variables it sets and
# the commands it runs first. Halon reads it from the repository's CI the first time it prepares the repository in the
# sandbox, and an admin reads it again, changes it or clears it under the code host connection. The sandbox starts the
# services it can, sets the variables and runs the commands before a coding agent writes a change or run_tests runs.
class RepositorySetup < ApplicationRecord
  MAX_SERVICES = 10
  MAX_VARIABLES = 100
  MAX_COMMANDS = 30
  COMMAND_LIMIT = 2_000
  VALUE_LIMIT = 2_000
  VARIABLE_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/
  SERVICE_NAME = /\A[a-z0-9][a-z0-9._-]{0,62}\z/
  # The sandbox sets these for every command, so a setup cannot.
  RESERVED_VARIABLES = %w[PATH HOME LANG GEM_HOME BUNDLE_APP_CONFIG BUNDLE_SILENCE_ROOT_WARNING GIT_TERMINAL_PROMPT SANDBOX_PROGRESS].freeze
  RESERVED_PREFIX = "MISE_".freeze

  # One service as the setup keeps it. port is where the repository's tests reach it, nil for its usual one.
  Service = Data.define(:name, :image, :port, :env) do
    def initialize(image: nil, port: nil, env: {}, **) = super

    def self.from(hash)
      hash = hash.to_h.stringify_keys
      port = hash["port"].presence && Integer(hash["port"].to_s, exception: false)
      new(name: hash["name"].to_s.strip.downcase, image: hash["image"].to_s.strip.presence, port: port, env: RepositorySetup.variables(hash["env"]))
    end

    def to_h = { "name" => name, "image" => image, "port" => port, "env" => env }.compact

    # What the sandbox is handed. A box that runs containers starts the service from its image, and another reads from
    # the image which Postgres extension the CI's tests expect.
    def for_box = to_h
  end

  belongs_to :workspace
  belongs_to :integration

  validates :repository, presence: true, uniqueness: { scope: :integration_id }

  def self.for(integration, repository) = find_by(integration: integration, repository: repository.to_s)

  # The services, variables and commands as a person or a CI file gave them, trimmed, with blank ones left out. A
  # command keeps its lines, since a CI step is one script.
  def self.normalized(services:, env:, commands:)
    {
      services: Array(services).map { |service| Service.from(service) }.reject { |service| service.name.blank? },
      env: variables(env),
      commands: Array(commands).map { |command| command.to_s.gsub("\r\n", "\n").strip }.compact_blank
    }
  end

  # Variables as a hash, from a hash or from name and value pairs as the page sends them.
  def self.variables(given) = pairs(given).reject { |name, _value| name.empty? }.to_h

  def self.pairs(given)
    case given
    when Hash then given.map { |name, value| [ name.to_s.strip, value.to_s ] }
    when Array then given.map { |pair| pair.to_h.stringify_keys.then { |each| [ each["name"].to_s.strip, each["value"].to_s ] } }
    else []
    end
  end

  # The first variable named twice, or nil.
  def self.repeated(given) = pairs(given).map(&:first).reject(&:empty?).tally.find { |_name, count| count > 1 }&.first

  # Why these cannot be a repository's setup, or nil when they can.
  def self.blocked_reason(services:, env:, commands:)
    given = normalized(services: services, env: env, commands: commands)
    repeated = repeated(env) || Array(services).lazy.filter_map { |service| repeated(service.to_h.stringify_keys["env"]) }.first
    return "#{repeated} is set twice. Keep one." if repeated
    return "List at most #{MAX_SERVICES} services." if given[:services].size > MAX_SERVICES
    return "Set at most #{MAX_VARIABLES} variables." if given[:env].size > MAX_VARIABLES
    return "List at most #{MAX_COMMANDS} commands." if given[:commands].size > MAX_COMMANDS

    given[:services].lazy.filter_map { |service| service_refusal(service) }.first ||
      given[:env].lazy.filter_map { |name, value| variable_refusal(name, value) }.first ||
      given[:commands].lazy.filter_map { |command| command_refusal(command) }.first
  end

  def self.service_refusal(service)
    return "#{service.name} is not a service name. Use lower case letters, digits, dots and dashes, such as postgres." unless service.name.match?(SERVICE_NAME)
    return "#{service.name}'s port must be a number from 1024 to 65535." if service.port && !service.port.between?(1024, 65_535)

    service.env.lazy.filter_map { |name, value| variable_refusal(name, value) }.first
  end

  def self.variable_refusal(name, value)
    return "#{name} is not a variable name. Use letters, digits and underscores, starting with a letter." unless name.match?(VARIABLE_NAME)
    return "The sandbox sets #{name} itself, so a setup cannot." if RESERVED_VARIABLES.include?(name) || name.start_with?(RESERVED_PREFIX)
    return "#{name} is longer than #{VALUE_LIMIT} characters." if value.length > VALUE_LIMIT

    if value.match?(Chat::SecretFree::CREDENTIAL_URL)
      return "#{name} holds a password. The sandbox's services take any password, so take it out, as in postgres://postgres@127.0.0.1:5432/app_test."
    end
    return unless Chat::SecretFree::SECRET_PATTERNS.values.any? { |pattern| value.match?(pattern) }

    "#{name} looks like it holds a credential, and Firefight keeps credentials only in a connection's settings, so it is not saved."
  end

  def self.command_refusal(command)
    "A command is longer than #{COMMAND_LIMIT} characters." if command.length > COMMAND_LIMIT
  end

  # Replaces the setup with what a person gave, answering why it was refused, or nil once it is saved.
  def change!(services:, env:, commands:)
    refusal = self.class.blocked_reason(services: services, env: env, commands: commands)
    return refusal if refusal

    given = self.class.normalized(services: services, env: env, commands: commands)
    update!(services: given[:services].map(&:to_h), env: given[:env], commands: given[:commands], edited_at: Time.current)
    nil
  end

  # Replaces the setup with what was read from the repository's CI, notes included.
  def derived!(services:, env:, commands:, source:, notes: [])
    given = self.class.normalized(services: services, env: env, commands: commands)
    update!(services: given[:services].map(&:to_h), env: given[:env], commands: given[:commands], notes: Array(notes),
            derived_from: source, derived_at: Time.current, edited_at: nil)
  end

  def service_list = services.map { |service| Service.from(service) }

  # The services the sandbox cannot start, which it leaves out when it prepares the repository. A sandbox that runs
  # containers (images) starts any service with an image.
  def unstartable_services(images: false)
    service_list.reject { |service| CodeBox::SERVICES.include?(service.name) || (images && service.image.present?) }.map(&:name)
  end

  # What the sandbox is handed when it prepares the repository and runs a command in it.
  def for_box = { "services" => service_list.map(&:for_box), "env" => env, "commands" => commands }

  # Changes whenever what the sandbox is handed changes, so what an earlier copy installed is used only with the same setup.
  def digest = Digest::SHA256.hexdigest(JSON.generate(for_box))
end
