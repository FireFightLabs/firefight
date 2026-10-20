# DigitalOcean's pack gained app_events and changes to cancel a deployment or a job run, redeploy an app and keep or undo
# a rollback. Trigger.dev's gained deploy_history and changes to cancel and replay runs, pause, resume and override queues
# and concurrency limits, and triage error groups. Discovery only runs on connect or refresh, so existing connections
# get them here. Native packs declare their tools locally, so this calls no provider.
class SyncDigitaloceanAndTriggerDevTools < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[digitalocean trigger_dev].freeze

  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDERS).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
