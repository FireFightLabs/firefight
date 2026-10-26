require "test_helper"

class Workspace::PullRequestReviewingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a code host's review tools are granted to Halon's review agent as they are minted, and nothing else" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
    Integrations::DiscoveryService.sync!(integration)

    held = Ability::Resolver.resolve(SystemAgent.pull_request_review, @workspace)
    review_keys = Integrations::PullRequestReviews.tools("gitlab").map { |name| integration.tools.find_by!(name: name).action_key }

    assert review_keys.all? { |key| held.covers?(key) }
    assert_not held.covers?(integration.tools.find_by!(name: "retry_pipeline").action_key)
  end

  test "repositories are chosen by name in any case, and choosing none is refused" do
    @workspace.update!(pull_request_reviews_on_open: Workspace::PullRequestReviewing::ON_OPEN_CHOSEN, pull_request_review_repositories: [ " Acme/Shop ", "acme/shop" ])
    assert_equal [ "acme/shop" ], @workspace.pull_request_review_repositories
    assert @workspace.reviews_on_open?("ACME/shop")

    @workspace.pull_request_review_repositories = []
    assert_not @workspace.valid?
    assert_includes @workspace.errors[:pull_request_review_repositories], Workspace::PullRequestReviewing::CHOSEN_NEEDS_ONE
  end
end
