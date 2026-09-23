# Registry data from config/integration_providers.yml.
class IntegrationProvider
  REGISTRY_PATH = Rails.root.join("config/integration_providers.yml")

  Entry = Data.define(:key, :name, :category, :mark, :color, :description, :server_url, :kind)

  def self.all
    @all ||= registry.fetch("providers").map do |raw|
      Entry.new(
        key: raw.fetch("key"), name: raw.fetch("name"), category: raw.fetch("category"),
        mark: raw.fetch("mark"), color: raw.fetch("color"),
        description: raw.fetch("description"), server_url: raw["server_url"].to_s,
        # kind: native runs through Integrations::NativePack instead of an MCP server.
        kind: raw["kind"] || Integration::KIND_MCP
      )
    end.freeze
  end

  def self.find(key)
    all.find { |entry| entry.key == key }
  end

  # Registry data, so a provider in a new category needs no code change.
  def self.categories
    @categories ||= registry.fetch("categories", {}).freeze
  end

  Category = Data.define(:slug, :name, :tagline)

  # A category as something a person or a model can name, by its slug or its name.
  def self.category_list
    @category_list ||= categories.map { |name, tagline| Category.new(slug: name.parameterize(separator: "_"), name: name, tagline: tagline) }.freeze
  end

  def self.category_for!(value)
    wanted = value.to_s.strip.downcase
    category_list.find { |category| category.slug == wanted || category.name.downcase == wanted } ||
      raise(ArgumentError, "Unknown category '#{value}'. One of: #{category_list.map { |category| "#{category.slug} (#{category.name})" }.join(', ')}")
  end

  STATE_CONNECTED = "connected".freeze
  STATE_NEEDS_ATTENTION = "needs_attention".freeze
  STATE_TURNED_OFF = "turned_off".freeze
  STATE_NOT_CONNECTED = "not_connected".freeze
  # Connected first, so a card also says what is already set up.
  STATES = [ STATE_CONNECTED, STATE_NEEDS_ATTENTION, STATE_TURNED_OFF, STATE_NOT_CONNECTED ].freeze

  Row = Data.define(:provider, :state, :connections)
  Card = Data.define(:category, :rows)

  # One category as a workspace sees it: every provider in it, and where each stands.
  def self.card_for(workspace, category)
    by_provider = workspace.integrations.where(deleted_at: nil).includes(:integration_environments).group_by(&:provider)
    rows = all.select { |provider| provider.category == category.name }.map do |provider|
      connections = by_provider.fetch(provider.key, [])
      Row.new(provider: provider, state: state_for(connections), connections: connections.map { |integration| { id: integration.id, name: integration.name } })
    end
    Card.new(category: category, rows: rows.sort_by.with_index { |row, index| [ STATES.index(row.state), index ] })
  end

  def self.cards_for(workspace)
    category_list.map { |category| card_for(workspace, category) }
  end

  def self.state_for(connections)
    return STATE_NOT_CONNECTED if connections.empty?

    live = connections.reject(&:disabled_at)
    return STATE_TURNED_OFF if live.empty?

    failing = live.any? { |integration| integration.integration_environments.any? { |row| row.enabled && row.health_status == IntegrationEnvironment::HEALTH_FAILING } }
    failing ? STATE_NEEDS_ATTENTION : STATE_CONNECTED
  end
  private_class_method :state_for

  def self.registry
    @registry ||= YAML.load_file(REGISTRY_PATH)
  end
  private_class_method :registry

  # Providers without dynamic registration, such as GitHub, read one Firefight-wide app from
  # INTEGRATION_<KEY>_CLIENT_ID and _CLIENT_SECRET. Tokens are still per workspace.
  def self.oauth_client(key)
    prefix = "INTEGRATION_#{key.to_s.upcase}"
    client_id = ENV["#{prefix}_CLIENT_ID"].presence ||
                Rails.application.credentials.dig(:integrations, key.to_sym, :client_id)
    return {} if client_id.blank?

    { client_id: client_id,
      client_secret: ENV["#{prefix}_CLIENT_SECRET"].presence ||
                     Rails.application.credentials.dig(:integrations, key.to_sym, :client_secret),
      # Set when the app must be installed before its tokens reach anything,
      # so connecting starts at the install screen.
      app_slug: ENV["#{prefix}_APP_SLUG"].presence ||
                Rails.application.credentials.dig(:integrations, key.to_sym, :app_slug),
      # PEM for providers that mint server tokens from a signed app JWT.
      private_key: ENV["#{prefix}_PRIVATE_KEY"].presence ||
                   Rails.application.credentials.dig(:integrations, key.to_sym, :private_key) }
  end
end
