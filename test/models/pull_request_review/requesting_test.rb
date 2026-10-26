require "test_helper"

class PullRequestReview::RequestingTest < ActiveJob::TestCase
  test "asking for a review queues one of the head through the connection, capped at what one of Halon's runs may spend, and asking again answers it" do
    workspace = workspaces(:slack_workspace_one)
    integration = Integration.create!(workspace: workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    row = integration.integration_environments.create!(base_config: { "installation_id" => "12345" })

    review = PullRequestReview.request!(row, repository: "acme/api", number: 7, head_sha: "a" * 40, trigger: PullRequestReview::TRIGGER_REQUESTED)

    assert_enqueued_with(job: PullRequestReviewJob, args: [ review.id ])
    assert_equal [ workspace, row, PullRequestReview::STATUS_QUEUED, workspace.investigation_limits.max_spend_cents ],
                 [ review.workspace, review.integration_environment, review.status, review.max_spend_cents ]
    assert_equal review, PullRequestReview.request!(row, repository: "acme/api", number: 7, head_sha: "b" * 40, trigger: PullRequestReview::TRIGGER_AUTOMATIC)
  end
end
