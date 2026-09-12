# Discovery only runs on connect or refresh, so existing connections miss tools added in code.
# Native packs declare their tools locally, so this calls no provider. New rows arrive disabled.
class SyncNativeIntegrationTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
