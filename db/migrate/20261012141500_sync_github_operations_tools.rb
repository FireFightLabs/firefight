# GitHub's pack gained reads (pending_deployments, repository_access, list_actions_variables, list_artifacts and
# read_artifact) and changes (update_release, publish_release, revert_pull_request, review_pending_deployment and
# clear_actions_cache). Discovery only runs on connect or refresh, so existing connections get them here. Native packs
# declare their tools locally, so this calls no provider.
class SyncGithubOperationsTools < ActiveRecord::Migration[8.1]
  PROVIDER = "github".freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDER).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
