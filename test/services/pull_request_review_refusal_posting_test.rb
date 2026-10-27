require "test_helper"

class PullRequestReviewRefusalPostingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  COMMENT = Integrations::PullRequestReviews::COMMENT
  Refusal = PullRequestReview::Refusal

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @posts = []
  end

  test "Halon says in a plain sentence on the pull request why it cannot review it, and keeps the comment" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    Integrations::PullRequestReviews.stubs(:call!).with { |row, called, **given| row == @row && called == COMMENT && (@posts << given) }.returns("300")

    PullRequestReviewRefusalPosting.new(refusal).post!

    assert_equal [ { repository: "acme/api", number: 7, body: "I can't read this repository, so I can't review it. An admin can give me access under Permissions." } ],
                 @posts.map { |given| given.except(:authorize) }
    assert_equal "300", refusal.reload.comment_id
    assert refusal.posted_at

    PullRequestReviewRefusalPosting.new(refusal).post!
    assert_equal 1, @posts.size, "a refusal is said once"
  end

  test "each reason a review cannot start has its own sentence, and none says anything internal" do
    sentences = Refusal::REASONS.index_with { |reason| PullRequestReview::Comments.refused(reason) }

    assert_equal "I can't review pull requests in this workspace right now. An admin can see why in Firefight.", sentences[Refusal::HALON_UNAVAILABLE]
    assert_equal "I can't review this yet, because the AI model I run on is not set up. An admin can finish setting it up in Firefight.", sentences[Refusal::MODEL_NOT_SET_UP]
    assert_nil sentences[Refusal::NO_CONNECTION], "a pull request no connection holds has nowhere to be told"
    sentences.values.compact.each { |sentence| assert_no_match(/[—;]/, sentence) }
  end

  test "a host that refuses for good is logged and never tried again, and one that turned it down for now is tried again" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    Integrations::PullRequestReviews.stubs(:call!).raises(Integrations::Error, "GitHub answered 403: Resource not accessible.")

    assert_nothing_raised { PullRequestReviewRefusalPosting.new(refusal).post! }
    assert_nil refusal.reload.posted_at

    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).raises(Integrations::Error.new("GitHub answered 429: slow down").extend(Integrations::RateLimited))
    assert_raises(PullRequestReviewRefusalPosting::Retry) { PullRequestReviewRefusalPosting.new(create_refusal(Refusal::NO_ACCESS, reference: "r2")).post! }
  end

  test "a comment an approval rule holds is posted once approved, and nothing is posted once declined" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    approval = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                         principal_label: "Halon pull request review", action_key: "github.comment_on_pull_request", request_digest: "d", scope: {}, params: {},
                                         required_role: WorkspaceMembership.roles[:admin])
    Integrations::PullRequestReviews.stubs(:call!).raises(AbilityGateway::PendingApproval.new(approval))

    PullRequestReviewRefusalPosting.new(refusal).post!

    assert_equal({ "kind" => ApprovalResumption::KIND_PULL_REQUEST_REVIEW_REFUSAL, "refusal_id" => refusal.id }, approval.reload.resume_payload)
    assert_nil refusal.reload.posted_at

    approval.update_columns(status: Ability::Approval::STATUS_APPROVED)
    assert_enqueued_with(job: PullRequestReviewRefusalPostJob, args: [ refusal.id, approval.id ]) { ApprovalResumption.resume!(approval) }

    approval.update_columns(status: Ability::Approval::STATUS_DENIED)
    assert_no_enqueued_jobs(only: PullRequestReviewRefusalPostJob) { ApprovalResumption.decline!(approval) }
  end

  test "the comment is one of the connection's tools, made as Halon's review agent through the gateway and in the activity log" do
    tool = @row.integration.tools.create!(name: "comment_on_pull_request", description: "Comments.", enabled: true, read_only: false)
    Ability::Grant.grant!(workspace: @workspace, principal: SystemAgent.pull_request_review, target: { action: tool.ability_action || tool.sync_ability_action! })
    Integrations::NativeExecutor.expects(:call).returns(Integrations::Telemetry.result("Commented.", link: nil, facts: { "comment_id" => 300 }))
    refusal = create_refusal(Refusal::NO_ACCESS)

    PullRequestReviewRefusalPosting.new(refusal).post!

    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: tool.action_key)
    assert_equal [ SystemAgent.pull_request_review.id, AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, Ability::Invocation::OUTCOME_SUCCESS, "PR #7 in acme/api" ],
                 [ invocation.principal_id, invocation.source, invocation.outcome, invocation.triggered_by_label ]
    assert_equal "300", refusal.reload.comment_id
  end

  private

  def create_refusal(reason, reference: "acme/api#7:asked:a")
    PullRequestReview::Refusal.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, reference: reference, reason: reason)
  end
end
