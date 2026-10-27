require "test_helper"

class PullRequestReview::StartTest < ActiveJob::TestCase
  include PullRequestReviewTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = review_connection(@workspace)
    Integrations::ReviewHost.stubs(:row_for).returns(nil)
    Integrations::ReviewHost.stubs(:row_for).with(@workspace, "acme/api").returns(@row)
    Integrations::ReviewHost.stubs(:pull_request).returns(review_pull)
    Investigation.stubs(:unavailable_reason).returns(nil)
  end

  test "a review of the pull request's head is queued, spending at most what one of Halon's runs may" do
    review = PullRequestReview::Start.call(workspace: @workspace, repository: "acme/api", number: 7, trigger: PullRequestReview::TRIGGER_REQUESTED)

    assert_enqueued_with(job: PullRequestReviewJob, args: [ review.id ])

    assert_equal [ @row, REVIEW_HEAD, REVIEW_BASE, "Retry checkout", PullRequestReview::STATUS_QUEUED ],
                 [ review.integration_environment, review.head_sha, review.base_sha, review.title, review.status ]
    assert_equal @workspace.investigation_limits.max_spend_cents, review.max_spend_cents
  end

  test "a pull request already under review answers the review that is running" do
    first = PullRequestReview::Start.call(workspace: @workspace, repository: "acme/api", number: 7, trigger: PullRequestReview::TRIGGER_REQUESTED)

    assert_equal first, PullRequestReview::Start.call(workspace: @workspace, repository: "acme/api", number: 7, trigger: PullRequestReview::TRIGGER_AUTOMATIC)
    assert_equal 1, @workspace.pull_request_reviews.count
  end

  test "a connection Halon may no longer read refuses the review with why, and reads nothing" do
    revoke_review_reads(@row)
    Integrations::ReviewHost.expects(:pull_request).never

    error = assert_raises(PullRequestReview::Start::Refused) do
      PullRequestReview::Start.call(workspace: @workspace, repository: "acme/api", number: 7, trigger: PullRequestReview::TRIGGER_REQUESTED)
    end
    assert_equal "Halon has no access to read GitHub, so it cannot review this pull request.", error.message
    assert_empty @workspace.pull_request_reviews
  end

  test "reading the pull request at the start is in the activity log under the review" do
    PullRequestReview::Start.call(workspace: @workspace, repository: "acme/api", number: 7, trigger: PullRequestReview::TRIGGER_REQUESTED)

    read = Ability::Invocation.find_by!(workspace: @workspace, action_key: Ability::Role.reads_key(@row.integration_id))
    assert_equal [ AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, "Review of PR #7 in acme/api", Ability::Invocation::OUTCOME_SUCCESS ],
                 [ read.source, read.triggered_by_label, read.outcome ]
  end

  test "a repository no connection holds, or a workspace without Halon, is refused with why" do
    error = assert_raises(PullRequestReview::Start::Refused) do
      PullRequestReview::Start.call(workspace: @workspace, repository: "acme/other", number: 1, trigger: PullRequestReview::TRIGGER_REQUESTED)
    end
    assert_equal "No code host connected to this workspace holds acme/other on its resource map, so Halon cannot read it.", error.message

    Investigation.stubs(:unavailable_reason).returns("AI features are not available.")
    assert_raises(PullRequestReview::Start::Refused) do
      PullRequestReview::Start.call(workspace: @workspace, repository: "acme/api", number: 7, trigger: PullRequestReview::TRIGGER_REQUESTED)
    end
  end
end
