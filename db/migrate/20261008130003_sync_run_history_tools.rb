# The packs of the code hosts and some platforms gained a read that lists their runs with when each started and finished,
# which run_history answers through. Discovery only runs on connect or refresh, so existing connections get them here.
# Native packs declare their tools locally, so this calls no provider.
class SyncRunHistoryTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
