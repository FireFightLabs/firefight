# The curated catalog behind Configure -> Integrations. Pure registry data
# (config/integration_providers.yml); connecting any entry goes through the
# generic MCP connector.
class IntegrationProvider
  REGISTRY_PATH = Rails.root.join("config/integration_providers.yml")

  Entry = Data.define(:key, :name, :category, :mark, :color, :description, :server_url)

  def self.all
    @all ||= YAML.load_file(REGISTRY_PATH).fetch("providers").map do |raw|
      Entry.new(
        key: raw.fetch("key"), name: raw.fetch("name"), category: raw.fetch("category"),
        mark: raw.fetch("mark"), color: raw.fetch("color"),
        description: raw.fetch("description"), server_url: raw["server_url"].to_s
      )
    end.freeze
  end

  def self.find(key)
    all.find { |entry| entry.key == key }
  end
end
