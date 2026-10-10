# Most packs gained api_read, a general read of the provider's API. Discovery only runs on connect or refresh, so
# existing connections get it here. Native packs declare their tools locally, so this calls no provider. A new tool
# arrives switched on, and joins each connection's read pack since it only reads.
class SyncGeneralReadTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
