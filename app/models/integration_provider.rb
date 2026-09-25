# Registry data from config/integration_providers.yml.
class IntegrationProvider
  REGISTRY_PATH = Rails.root.join("config/integration_providers.yml")

  # connect_with names a connect flow other than OAuth or an app install. A connection URL is pasted per environment.
  # An API token, and whatever else the provider asks for, is typed per environment.
  CONNECT_CONNECTION_URL = "connection_url".freeze
  CONNECT_API_TOKEN = "api_token".freeze
  CONNECT_WITH = [ CONNECT_CONNECTION_URL, CONNECT_API_TOKEN ].freeze

  Entry = Data.define(:key, :name, :category, :mark, :color, :description, :server_url, :kind, :connect_with) do
    def initialize(connect_with: nil, **) = super

    def connection_url? = connect_with == CONNECT_CONNECTION_URL

    def api_token? = connect_with == CONNECT_API_TOKEN
  end

  def self.all
    @all ||= registry.fetch("providers").map do |raw|
      Entry.new(
        key: raw.fetch("key"), name: raw.fetch("name"), category: raw.fetch("category"),
        mark: raw.fetch("mark"), color: raw.fetch("color"),
        description: raw.fetch("description"), server_url: raw["server_url"].to_s,
        # kind: native runs through Integrations::NativePack instead of an MCP server.
        kind: raw["kind"] || Integration::KIND_MCP,
        connect_with: raw["connect_with"]
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
    @category_list ||= categories.map { |name, tagline| Category.new(slug: category_slug(name), name: name, tagline: tagline) }.freeze
  end

  # What a category is called wherever it is a key: the agent's tool groups, a card, a tool parameter.
  def self.category_slug(name) = name.parameterize(separator: "_")

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

  STATE_LABELS = {
    STATE_CONNECTED => "Connected", STATE_NEEDS_ATTENTION => "Needs attention",
    STATE_TURNED_OFF => "Turned off", STATE_NOT_CONNECTED => "Not connected"
  }.freeze

  # What a person can do from a row. Connecting is offered where nothing works yet, managing where something does.
  ACTION_CONNECT = "connect".freeze
  ACTION_RECONNECT = "reconnect".freeze
  ACTION_MANAGE = "manage".freeze
  ACTIONS = [ ACTION_CONNECT, ACTION_RECONNECT, ACTION_MANAGE ].freeze
  ACTION_LABELS = { ACTION_CONNECT => "Connect", ACTION_RECONNECT => "Reconnect", ACTION_MANAGE => "Manage" }.freeze
  ACTION_BY_STATE = {
    STATE_CONNECTED => ACTION_MANAGE, STATE_NEEDS_ATTENTION => ACTION_RECONNECT,
    STATE_TURNED_OFF => ACTION_MANAGE, STATE_NOT_CONNECTED => ACTION_CONNECT
  }.freeze

  Row = Data.define(:provider, :state, :connections) do
    def state_label = STATE_LABELS.fetch(state)

    def action = ACTION_BY_STATE.fetch(state)

    def action_label = ACTION_LABELS.fetch(action)

    def opens_connect? = action != ACTION_MANAGE
  end
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
