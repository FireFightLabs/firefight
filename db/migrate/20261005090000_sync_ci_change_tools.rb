# GitHub's pack can now rerun, start and cancel a workflow run, and GitLab's and Bitbucket's can run a pipeline again,
# run one and cancel one. Discovery only runs on connect or refresh, so existing connections get them here. Native packs
# declare their tools locally, so this calls no provider. The new tools change things, so they arrive disabled.
class SyncCiChangeTools < ActiveRecord::Migration[8.1]
  def up
    Integration.where(kind: Integration::KIND_NATIVE).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
