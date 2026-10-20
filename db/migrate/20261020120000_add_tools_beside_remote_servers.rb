# A provider reached through its MCP server may have Firefight's own tools beside the server's, which PlanetScale and
# Supabase gained (Integrations::NativePack.beside_server?). Discovery only runs on connect or refresh, so existing
# connections get them here, saved beside the server's tools as last listed, without calling any server. A new tool
# arrives switched on, as at connect.
class AddToolsBesideRemoteServers < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_MCP, deleted_at: nil).find_each do |integration|
      Integrations::DiscoveryService.add_beside!(integration)
    end
  end

  def down
  end
end
