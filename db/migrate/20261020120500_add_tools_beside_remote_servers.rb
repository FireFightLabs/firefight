# A provider reached through its MCP server may have Firefight's own tools beside the server's (Integrations::Provider
# #firefight_tools), which PlanetScale and Supabase gained. Discovery only runs on connect or refresh, so existing
# connections get them here, without calling any server, every tool the server listed left as it is. A new tool arrives
# switched on, as at connect.
class AddToolsBesideRemoteServers < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_MCP, deleted_at: nil).find_each do |integration|
      Integrations::DiscoveryService.add_firefight_tools!(integration)
    end
  end

  def down
  end
end
