# Cloudflare gained named tools beside its server's own (Integrations::Provider#firefight_tools, named_tools), after the
# connections Firefight's own tools were last given to. Discovery only runs on connect or refresh, so existing connections
# get them here through the shared helper, without calling any server, every tool the server listed left as it is. A new
# tool arrives switched on, as at connect.
class SyncNamedTools < ActiveRecord::Migration[8.1]
  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_MCP, deleted_at: nil).find_each do |integration|
      Integrations::DiscoveryService.add_firefight_tools!(integration)
    end
  end

  def down
  end
end
