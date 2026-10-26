# GitHub's, GitLab's and Bitbucket's packs gained the tools Halon posts a pull request review through: a comment, an edit
# of one Firefight wrote, a review with comments on lines, a reply in a thread and a thread resolved. Discovery only runs
# on connect or refresh, so existing connections get them here, and Halon's review agent is granted those tools and the
# two reads it checks a fix with on every existing connection. Native packs declare their tools locally, so this calls
# no provider.
class SyncCodeHostReviewTools < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[github gitlab bitbucket].freeze

  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDERS, deleted_at: nil).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
      integration.workspace.grant_pull_request_reviewing!(integration)
    end
  end

  def down
  end
end
