# Each code host's pack gained a read of a pull request's conversation, which Halon's review agent reads before posting
# again a comment a call that did not answer may have posted. Discovery only runs on connect or refresh, so existing
# connections get it here, and the review agent is granted it. Native packs declare their tools locally, so this calls
# no provider.
class SyncReviewConversationReadBack < ActiveRecord::Migration[8.1]
  def up
    Ability::Role.reset_column_information
    Integration.where(kind: Integration::KIND_NATIVE, deleted_at: nil).find_each do |integration|
      next if Integrations::PullRequestReviews.tools(integration.provider).empty?

      Integrations::DiscoveryService.sync!(integration)
      integration.workspace.grant_pull_request_reviewing!(integration)
    end
  end

  def down
  end
end
