# Tinybird's pack gained a read of the workspace's deployments, and the PostgreSQL pack one of what went wrong in the
# database. Discovery only runs on connect or refresh, so existing connections get them here. Native packs declare
# their tools locally, so this calls no provider.
class SyncDatabaseErrorsAndDeploymentsTools < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[tinybird postgresql].freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDERS).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
