# ClickHouse, Neon, Turso and Upstash gained Firefight's own tools beside their MCP servers' (Integrations::Provider#firefight_tools),
# such as scaling a ClickHouse service or restoring a Neon branch to a moment. Discovery only runs on connect or refresh,
# so existing connections get them here, saved beside the server's tools as last listed, without calling any server.
class AddDatabaseToolsBesideTheirServers < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[clickhouse neon turso upstash].freeze

  def up
    Integration.where(kind: Integration::KIND_MCP, provider: PROVIDERS, deleted_at: nil).find_each do |integration|
      Integrations::DiscoveryService.add_firefight_tools!(integration)
    end
  end

  def down
  end
end
