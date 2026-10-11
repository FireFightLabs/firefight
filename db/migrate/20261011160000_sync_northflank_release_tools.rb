# Northflank's pack gained reads of workflow runs, release flow runs and database backups, which run history answers
# through, and its other tools now take jobs. Discovery only runs on connect or refresh, so existing connections get them
# here. Native packs declare their tools locally, so this calls no provider.
class SyncNorthflankReleaseTools < ActiveRecord::Migration[8.1]
  PROVIDER = "northflank".freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDER).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
