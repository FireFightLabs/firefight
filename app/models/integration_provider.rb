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
