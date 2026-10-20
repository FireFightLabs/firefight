# Firefight added tools of its own to a remote server's connection (Integrations::NamedTools), which discovery saves only
# on connect or refresh, so connections made before get them here, switched on as a newly discovered tool is. Only those
# tools are saved, without asking any server, and a connection whose provider adds none is left as it is.
class SyncNamedTools < ActiveRecord::Migration[8.1]
  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_MCP).find_each do |integration|
      Integrations::DiscoveryService.sync_named!(integration)
    end
  end

  def down
  end
end
