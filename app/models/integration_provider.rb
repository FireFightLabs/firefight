# The curated catalog behind Configure -> Integrations. Pure registry data
# (config/integration_providers.yml); connecting any entry goes through the
# generic MCP connector.
class IntegrationProvider
  REGISTRY_PATH = Rails.root.join("config/integration_providers.yml")

  Entry = Data.define(:key, :name, :category, :mark, :color, :description, :server_url, :kind)

  def self.all
    @all ||= registry.fetch("providers").map do |raw|
      Entry.new(
        key: raw.fetch("key"), name: raw.fetch("name"), category: raw.fetch("category"),
        mark: raw.fetch("mark"), color: raw.fetch("color"),
        description: raw.fetch("description"), server_url: raw["server_url"].to_s,
        # kind: native marks a provider that executes through a first-party
        # pack (Integrations::NativePack) instead of an MCP server.
        kind: raw["kind"] || Integration::KIND_MCP
      )
    end.freeze
  end

  def self.find(key)
    all.find { |entry| entry.key == key }
  end

  # Section name => tagline, for the gallery headings. Registry data so a
  # provider in a new category needs no code change.
  def self.categories
    @categories ||= registry.fetch("categories", {}).freeze
  end

  def self.registry
    @registry ||= YAML.load_file(REGISTRY_PATH)
  end
  private_class_method :registry

  # Providers whose OAuth server needs a pre-registered app (e.g. GitHub,
  # which has no dynamic registration) read a Firefight-wide client id and
  # secret from the environment (Infisical injects these as env vars), named
  #   INTEGRATION_<KEY>_CLIENT_ID / INTEGRATION_<KEY>_CLIENT_SECRET
  # e.g. INTEGRATION_GITHUB_CLIENT_ID. One app per provider serves every
  # workspace; the resulting tokens are per-workspace. Absent = fall back to
  # dynamic registration, else the token path.
  def self.oauth_client(key)
    prefix = "INTEGRATION_#{key.to_s.upcase}"
    client_id = ENV["#{prefix}_CLIENT_ID"].presence ||
                Rails.application.credentials.dig(:integrations, key.to_sym, :client_id)
    return {} if client_id.blank?

    { client_id: client_id,
      client_secret: ENV["#{prefix}_CLIENT_SECRET"].presence ||
                     Rails.application.credentials.dig(:integrations, key.to_sym, :client_secret),
      # Set for providers whose app must be installed before its tokens reach
      # anything (GitHub). Connecting then starts at the provider's install
      # screen instead of a bare authorize page.
      app_slug: ENV["#{prefix}_APP_SLUG"].presence ||
                Rails.application.credentials.dig(:integrations, key.to_sym, :app_slug) }
  end
end
