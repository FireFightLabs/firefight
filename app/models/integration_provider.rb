# Registry data from config/integration_providers.yml.
class IntegrationProvider
  REGISTRY_PATH = Rails.root.join("config/integration_providers.yml")

  # connect_with names a connect flow other than OAuth or an app install. A connection URL is pasted per environment.
  # An API token, and whatever else the provider asks for, is typed per environment.
  CONNECT_CONNECTION_URL = "connection_url".freeze
  CONNECT_API_TOKEN = "api_token".freeze
  CONNECT_WITH = [ CONNECT_CONNECTION_URL, CONNECT_API_TOKEN ].freeze

  # How a result links back to its page. config/integration_providers.yml says what each value means.
  SOURCE_LINKS_FIREFIGHT = "firefight".freeze
  SOURCE_LINKS_SERVER = "server".freeze
  SOURCE_LINKS_NONE = "none".freeze
  SOURCE_LINKS_UNCHECKED = "unchecked".freeze
  SOURCE_LINKS = [ SOURCE_LINKS_FIREFIGHT, SOURCE_LINKS_SERVER, SOURCE_LINKS_NONE, SOURCE_LINKS_UNCHECKED ].freeze
  # These say why in source_links_note, since neither is Firefight's own code.
  SOURCE_LINKS_EXPLAINED = [ SOURCE_LINKS_SERVER, SOURCE_LINKS_NONE ].freeze

  # Whether what a provider holds is on the resource map. config/integration_providers.yml says what each value means.
  MAP_FIREFIGHT = "firefight".freeze
  MAP_NONE = "none".freeze
  MAP_UNCHECKED = "unchecked".freeze
  MAPS = [ MAP_FIREFIGHT, MAP_NONE, MAP_UNCHECKED ].freeze
  MAP_EXPLAINED = [ MAP_NONE ].freeze

  # read_only_tools names tools a provider's server does not mark read only although they only read, so they are
  # treated as reads rather than as writes that each ask to be confirmed.

  # One place a provider runs its service, such as Datadog's EU1, for a provider that offers several. The connect dialog
  # offers the choice when there is more than one, and the connection keeps it. server_url is its MCP server, site the
  # address of the provider's app there, which links open, and authorization_endpoint and token_endpoint its OAuth
  # endpoints where they are not the ones its server names.
  Region = Data.define(:key, :label, :server_url, :site, :authorization_endpoint, :token_endpoint) do
    def initialize(server_url: "", site: nil, authorization_endpoint: nil, token_endpoint: nil, **) = super

    def host
      URI.parse(server_url.to_s).host&.downcase
    rescue URI::InvalidURIError
      nil
    end
  end

  # Firefight's own OAuth application with a provider, registered once by whoever runs Firefight, which connects a
  # provider natively to keep incident items in step with it (Integrations::Issues) beside the provider's own MCP server.
  # scopes are joined with scope_separator, params go on the authorization URL as the provider documents them, pkce says
  # whether the provider takes a code challenge, and token_format whether its token endpoint takes form or JSON. Its
  # client id and secret are INTEGRATION_<KEY>_APP_CLIENT_ID and INTEGRATION_<KEY>_APP_CLIENT_SECRET.
  App = Data.define(:label, :authorization_endpoint, :token_endpoint, :scopes, :scope_separator, :params, :pkce, :token_format) do
    def initialize(scopes: [], scope_separator: " ", params: {}, pkce: false, token_format: "form", **) = super

    def scope = scopes.join(scope_separator)
    def json_token? = token_format == "json"
  end

  # What the connect form asks beside the credentials, such as the account an environment reads. None is a secret.
  #
  # A field marked path names a part of the server's address, appended to it in the order the fields are listed, and a
  # field with query is the address's query parameter of that name. Both belong to the connection. A field with learned
  # is chosen after connecting, from what the connection's health check learned under that key (a list of value and
  # label), on the connection's details. Every other field belongs to the environment it was connected for.
  #
  # pattern is the shape a value must have, matched whole, and allowed says in words what it allows, for the form to
  # say when a value does not fit. A path field without a pattern of its own takes a slug's, so no value can carry a
  # slash, a query or a fragment into the address and reach somewhere else. default is what a field left empty holds,
  # so a field with one may be left empty.
  SLUG_PATTERN = "[A-Za-z0-9][A-Za-z0-9._-]*".freeze
  SLUG_ALLOWED = "letters, numbers, dots, dashes and underscores, starting with a letter or number".freeze
  # One choice of a field that picks from a list, such as one of a cloud's regions.
  ConnectOption = Data.define(:value, :label)
  # options makes a field a choice from that list, and multiple lets it hold several, kept as a list, such as every
  # region an account runs in.
  ConnectField = Data.define(:key, :label, :hint, :placeholder, :numeric, :optional, :path, :query, :pattern, :allowed, :options, :multiple,
                             :default, :learned) do
    def initialize(placeholder: "", numeric: false, optional: false, path: false, query: nil, pattern: nil, allowed: nil, options: [],
                   multiple: false, default: nil, learned: nil, **)
      raise ArgumentError, "connect field #{key} has a pattern without saying in allowed what it allows" if pattern.present? && allowed.blank?
      raise ArgumentError, "connect field #{key} holds several values without a list to choose them from" if multiple && options.empty? && learned.blank?
      raise ArgumentError, "connect field #{key} is part of the address, so it holds one value" if (path || query.present?) && multiple
      raise ArgumentError, "connect field #{key} is both part of the address's path and its query" if path && query.present?
      raise ArgumentError, "connect field #{key} is chosen after connecting, so it cannot be part of the address" if learned.present? && (path || query.present?)

      options = options.map { |option| option.is_a?(ConnectOption) ? option : ConnectOption.new(**option.to_h.symbolize_keys) }
      pattern, allowed = SLUG_PATTERN, SLUG_ALLOWED if path && pattern.blank? && options.empty?
      default = default&.to_s
      optional ||= default.present?
      # A field that picks from a list shows its default by the option's label, any other by the value itself.
      placeholder = options.find { |option| option.value == default }&.label || default if placeholder.blank? && default.present?
      super(placeholder:, numeric:, optional:, path:, query: query.presence, pattern:, allowed:, options:, multiple:, default:,
            learned: learned.presence, **)
    end

    def address? = path || query.present?

    # A value as the form gave it, trimmed. A field that holds several gives a list, any other one string.
    def value_of(given)
      return Array(given).map { |each| each.to_s.strip }.compact_blank.uniq if multiple

      given.to_s.strip
    end

    # The choices a field offers. A field chosen after connecting offers the list its connection learned, any other its own.
    def options_from(learned_values)
      return options unless learned

      Array(learned_values.to_h[learned]).filter_map { |option| ConnectOption.new(value: option["value"].to_s, label: option["label"].to_s) if option.is_a?(Hash) }
    end

    # Why the form cannot go ahead with this value, or nil when it can. choices are what a field chosen after connecting
    # offers, from what its connection learned.
    def refusal(given, choices: options)
      value = value_of(given)
      return if value.empty? && optional
      return "#{label} is required." if value.empty?
      return "#{label} can only be #{choices.map(&:label).to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}." if (choices.any? || learned) && (Array(value) - choices.map(&:value)).any?
      return "#{label} must be a number." if numeric && !value.match?(/\A\d+\z/)

      "#{label} can hold only #{allowed}." if pattern && !value.match?(/\A(?:#{pattern})\z/)
    end

    # The value as given, or the field's default when it was left empty, as settings.field reads it.
    def value_or_default(given) = value_of(given).presence || default.to_s

    # How a value reads to a person, by its options' labels where it has them.
    def shown(value, choices: options) = Array(value).map { |each| choices.find { |option| option.value == each }&.label || each }.join(", ")
  end

  # site is the address of the provider's app, which links open, for a provider that runs in one place. A provider with
  # regions has a site per region instead.
  Entry = Data.define(:key, :name, :category, :mark, :color, :description, :server_url, :kind, :connect_with, :read_only_tools,
                      :source_links, :source_links_note, :map, :map_note, :code_fix_tool, :regions, :connect_fields, :site, :code_agent,
                      :app) do
    def initialize(connect_with: nil, read_only_tools: [], source_links_note: nil, map_note: nil, code_fix_tool: nil, regions: [],
                   connect_fields: [], site: nil, code_agent: false, app: nil, **) = super

    # A provider reached through its MCP server that Firefight's own app also connects, once this install registered it.
    def app_connect? = kind == Integration::KIND_MCP && app.present? && IntegrationProvider.app_client(key).present?

    # A native provider connected with credentials that also has an MCP server of its own, which a person may connect
    # through instead.
    def mcp_alternative? = kind == Integration::KIND_NATIVE && api_token? && server_url.present?

    # How a connection is made. It goes through the provider's MCP server when that was asked for and it has one, and its own
    # way otherwise.
    def connect_kind(asked)
      return Integration::KIND_MCP if asked.to_s == Integration::KIND_MCP && mcp_alternative?
      return Integration::KIND_NATIVE if asked.to_s == Integration::KIND_NATIVE && app_connect?

      kind
    end

    def connection_url? = connect_with == CONNECT_CONNECTION_URL

    def api_token? = connect_with == CONNECT_API_TOKEN

    # Whether the connect dialog asks which region, which it does only when there is more than one.
    def regional? = regions.size > 1

    # The region by its key. Without a key, the first one listed. nil for a provider without regions or a key it does not have.
    def region(key = nil) = key.present? ? regions.find { |each| each.key == key.to_s } : regions.first

    # The region whose server is at the address's host, for a connection made by pasting the server's address.
    def region_for_url(url)
      host = URI.parse(url.to_s).host&.downcase
      host && regions.find { |each| each.host == host }
    rescue URI::InvalidURIError
      nil
    end

    # The fields that are part of the server's address, in its path or its query, which belong to the connection.
    def address_fields = connect_fields.select(&:address?)

    # The fields the connect form asks for an environment.
    def environment_fields = connect_fields.reject { |field| field.address? || field.learned }

    # The fields chosen after connecting, from what the connection learned.
    def learned_fields = connect_fields.select(&:learned)

    # The fields a connect form asks, for a connection made the provider's own way or, reaching a native provider's MCP
    # server instead, none, since its fields are the native connection's.
    def asked_fields(kind = self.kind) = kind == self.kind ? connect_fields.reject(&:learned) : []

    # The values the form gave for fields, trimmed, keeping only the fields asked about and leaving out empty ones.
    def connect_values(values, fields = asked_fields)
      given = values.to_h.stringify_keys
      fields.to_h { |field| [ field.key, field.value_of(given[field.key]) ] }.compact_blank
    end

    # Why the connect form cannot go ahead with this region and these values, or nil when it can. fields are the ones
    # the form asked, since the form for a pasted server address does not ask the fields that are part of the address.
    def connect_refusal(region_key, values, fields = asked_fields)
      if region_key.present? && regions.any? && region(region_key).nil?
        return "#{name} has no region called #{region_key}. Choose one of #{regions.map(&:label).to_sentence(two_words_connector: ' or ', last_word_connector: ' or ')}."
      end

      given = values.to_h.stringify_keys
      fields.filter_map { |field| field.refusal(given[field.key]) }.first
    end

    # The server's address for a region and the fields that are part of it. Path fields are appended in the order they
    # are listed, and an optional one left empty ends the path there, so a later one never takes its place. Query fields
    # join the address's own query, and one left empty is left out. A field left empty with a default takes its default,
    # so the address matches what ConnectionSettings#field answers. Each value is escaped as well as checked, so it can
    # only ever be one segment or one parameter of the address.
    def server_url_for(region_key, values)
      given = values.to_h.stringify_keys
      uri = URI.parse((region(region_key)&.server_url || server_url).to_s)
      parts = connect_fields.select(&:path).map { |field| field.value_or_default(given[field.key]) }.take_while(&:present?)
      uri.path = [ uri.path.chomp("/"), *parts.map { |part| ERB::Util.url_encode(part) } ].join("/") if parts.any?
      query = connect_fields.select(&:query).filter_map do |field|
        value = field.value_or_default(given[field.key])
        [ field.query, value ] if value.present?
      end
      uri.query = URI.encode_www_form(URI.decode_www_form(uri.query.to_s) + query) if query.any?
      uri.to_s
    end
  end

  def self.all
    @all ||= registry.fetch("providers").map do |raw|
      regions = regions_of(raw)
      Entry.new(
        key: raw.fetch("key"), name: raw.fetch("name"), category: raw.fetch("category"),
        mark: raw.fetch("mark"), color: raw.fetch("color"),
        # A provider with regions has the first one's server, so a connection that names none reaches the same place.
        description: raw.fetch("description"), server_url: regions.first&.server_url || raw["server_url"].to_s,
        # kind: native runs through Integrations::NativePack instead of an MCP server.
        kind: raw["kind"] || Integration::KIND_MCP,
        connect_with: raw["connect_with"], read_only_tools: Array(raw["read_only_tools"]),
        source_links: declared(raw, "source_links", SOURCE_LINKS, SOURCE_LINKS_EXPLAINED), source_links_note: raw["source_links_note"],
        map: declared(raw, "map", MAPS, MAP_EXPLAINED), map_note: raw["map_note"],
        # The tool of a code host's pack that writes a change and opens it for review, which a fix's code steps run.
        code_fix_tool: raw["code_fix_tool"].presence,
        regions: regions, connect_fields: connect_fields_of(raw), site: raw["site"].presence,
        # A coding agent writes a change for any repository in its own environment and opens the pull request itself.
        # It writes a fix's code changes only once an admin chooses it under Settings, Workspace.
        code_agent: raw["code_agent"] == true,
        app: raw["app"] && App.new(**raw["app"].symbolize_keys)
      )
    end.freeze
  end

  # A provider lists its regions or its server_url, never both, and a region a connection keeps by its key has one.
  def self.regions_of(raw)
    regions = Array(raw["regions"]).map { |region| Region.new(**region.symbolize_keys) }
    return regions if regions.empty?

    raise ArgumentError, "#{raw['key']} lists regions and a server_url, and the regions' servers are the ones it has" if raw["server_url"].present?
    raise ArgumentError, "#{raw['key']} lists regions and a site, and the regions' sites are the ones it has" if raw["site"].present?
    raise ArgumentError, "#{raw['key']} lists a region key twice" unless regions.map(&:key).uniq.size == regions.size

    regions
  end

  def self.connect_fields_of(raw)
    fields = Array(raw["connect_fields"]).map { |field| ConnectField.new(**field.symbolize_keys) }
    raise ArgumentError, "#{raw['key']} lists a connect field key twice" unless fields.map(&:key).uniq.size == fields.size

    fields
  end
  private_class_method :regions_of, :connect_fields_of

  # A provider that says nothing, or something the rule does not know, fails at load rather than being skipped quietly.
  # field is source_links or map, and a value that is not Firefight's own work says why in the field's note.
  def self.declared(raw, field, allowed, explained)
    value = raw.fetch(field)
    raise ArgumentError, "#{raw['key']} declares #{field} #{value.inspect}, one of #{allowed.join(', ')}" unless allowed.include?(value)
    raise ArgumentError, "#{raw['key']} declares #{field} #{value} without a #{field}_note saying why" if explained.include?(value) && raw["#{field}_note"].blank?

    value
  end

  def self.find(key)
    all.find { |entry| entry.key == key }
  end

  def self.coding_agents = all.select(&:code_agent)

  # A code host's pack writes a change in Firefight's sandbox for the repositories its connection sees.
  def self.code_hosts = all.select { |entry| entry.code_fix_tool && !entry.code_agent }

  # Registry data, so a provider in a new category needs no code change. A category no provider is in yet is left out,
  # so neither the gallery nor Halon's tool groups show it empty.
  def self.categories
    @categories ||= registry.fetch("categories", {}).select { |name, _tagline| all.any? { |entry| entry.category == name } }.freeze
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
  # Firefight's own app with the provider (App), as INTEGRATION_<KEY>_APP_CLIENT_ID and _APP_CLIENT_SECRET name it, or
  # empty when this install registered none.
  def self.app_client(key)
    prefix = "INTEGRATION_#{key.to_s.upcase}_APP"
    client_id = ENV["#{prefix}_CLIENT_ID"].presence
    return {} if client_id.blank?

    { client_id: client_id, client_secret: ENV["#{prefix}_CLIENT_SECRET"].presence }
  end

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
