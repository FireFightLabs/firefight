# Northflank's pack gained the team's templates: template_runs, which run history answers through, and run_template and
# abort_template_run, two changes. Discovery only runs on connect or refresh, so existing connections get them here.
# Native packs declare their tools locally, so this calls no provider.
class SyncNorthflankTemplateTools < ActiveRecord::Migration[8.1]
  PROVIDER = "northflank".freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDER).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
