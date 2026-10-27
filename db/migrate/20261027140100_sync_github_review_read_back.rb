# GitHub's pack gained list_review_comments, which Halon's review agent reads a review's line comments back with when
# GitHub did not say their ids. Discovery only runs on connect or refresh, so existing connections get it here, and the
# review agent is granted it. Native packs declare their tools locally, so this calls no provider.
class SyncGithubReviewReadBack < ActiveRecord::Migration[8.1]
  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_NATIVE, provider: "github", deleted_at: nil).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
      integration.workspace.grant_pull_request_reviewing!(integration)
    end
  end

  def down
  end
end
