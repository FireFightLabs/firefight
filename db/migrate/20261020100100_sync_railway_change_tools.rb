# Railway's pack gained cron_runs and search_traces, two reads, and cancel_deployment, stop_deployment,
# redeploy_deployment and approve_deployment, four changes, and its tools take another environment of the project.
# Discovery only runs on connect or refresh, so existing connections get them here. Native packs declare their tools
# locally, so this calls no provider.
class SyncRailwayChangeTools < ActiveRecord::Migration[8.1]
  PROVIDER = "railway".freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDER).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
