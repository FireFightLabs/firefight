# GitHub's, GitLab's and Bitbucket's packs gained reads (environments, releases, tags and test reports) and changes
# (rerunning, starting or canceling one job, deploying an earlier deployment again, approving a deployment and stopping
# an environment). Discovery only runs on connect or refresh, so existing connections get them here. Native packs
# declare their tools locally, so this calls no provider.
class SyncCodeHostDeployTools < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[github gitlab bitbucket].freeze

  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDERS).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
