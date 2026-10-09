# Discovery only runs on connect or refresh, so existing PostgreSQL connections would miss database_status. The pack
# declares its tools locally, so this calls no database. New tools arrive switched on, and join each connection's packs
# by whether they only read.
class SyncPostgresStatusTool < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: Integrations::Packs::Postgres::PROVIDER).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
