require "test_helper"

class PullRequestReviewRefusalPostingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  COMMENT = Integrations::PullRequestReviews::COMMENT
  CONVERSATION = Integrations::PullRequestReviews::CONVERSATION
  Refusal = PullRequestReview::Refusal
  Signal = Integrations::PullRequestReviews::Signal
  SENTENCE = "I can't read this repository, so I can't review it. An admin can give me access under Permissions.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    Integrations::GithubApp.stubs(:bot_login).returns("firefight-app[bot]")
    @posts = []
  end

  test "Halon says in a plain sentence on the pull request why it cannot review it, and keeps the comment" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    Integrations::PullRequestReviews.stubs(:call!).with { |row, called, **given| row == @row && called == COMMENT && (@posts << given) }.returns("300")

    PullRequestReviewRefusalPosting.new(refusal).post!

    assert_equal [ { repository: "acme/api", number: 7, body: SENTENCE } ], @posts.map { |given| given.except(:authorize) }
    assert_equal [ "300", Refusal::STATUS_POSTED ], refusal.reload.values_at(:comment_id, :status)
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

  test "a host that refuses for good drops the comment with why, and one that is temporary is tried again" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    Integrations::PullRequestReviews.stubs(:call!).raises(answered(403, "GitHub answered 403: Resource not accessible."))

    assert_nothing_raised { PullRequestReviewRefusalPosting.new(refusal).post! }
    assert_equal [ Refusal::STATUS_DROPPED, "GitHub answered 403: Resource not accessible." ], refusal.reload.values_at(:status, :dropped_reason)

    [ Integrations::Error.new("GitHub answered 429: slow down").extend(Integrations::RateLimited),
      Integrations::Error.new("could not reach api.github.com (Errno::ECONNRESET)").extend(Integrations::Unreachable),
      answered(502, "GitHub answered 502 with something that is not JSON") ].each_with_index do |error, index|
      Integrations::PullRequestReviews.unstub(:call!)
      Integrations::PullRequestReviews.stubs(:call!).raises(error)
      temporary = create_refusal(Refusal::NO_ACCESS, reference: "r#{index}")

      assert_raises(PullRequestReviewRefusalPosting::Retry) { PullRequestReviewRefusalPosting.new(temporary).post! }
      assert_equal Refusal::STATUS_PENDING, temporary.reload.status
    end
  end

  test "an installation Firefight's app cannot act through drops the comment and is never tried again" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    Integrations::PullRequestReviews.stubs(:call!).raises(Integrations::PullRequestReviews::Stopped, "comment_on_pull_request was not run. The app is suspended.")

    assert_nothing_raised { PullRequestReviewRefusalPosting.new(refusal).post! }
    assert_equal Refusal::STATUS_DROPPED, refusal.reload.status
  end

  test "a try that may have posted reads the conversation first, keeps a comment found there and never posts twice" do
    comment_tool, list_tool = review_tools!
    refusal = create_refusal(Refusal::NO_ACCESS)
    timed_out = Integrations::Error.new("could not reach api.github.com (Net::ReadTimeout)").extend(Integrations::TimedOut)
    Integrations::NativeExecutor.stubs(:call).with { |tool:, **| tool == comment_tool && (@posts << tool.name) }.raises(timed_out)

    assert_raises(PullRequestReviewRefusalPosting::Retry) { PullRequestReviewRefusalPosting.new(refusal).post! }
    assert refusal.reload.attempted_at

    travel 2.minutes
    listed = [ { "id" => 299, "url" => nil, "body" => SENTENCE, "authors" => [ "ada" ], "at" => 1.minute.ago.iso8601 },
               { "id" => 300, "url" => "https://github.com/acme/api/pull/7#issuecomment-300", "body" => SENTENCE, "authors" => [ "firefight-app[bot]" ], "at" => 1.minute.ago.iso8601 } ]
    Integrations::NativeExecutor.stubs(:call).with { |tool:, arguments:, **| tool == list_tool && Time.zone.parse(arguments["since"]) <= refusal.attempted_at }
                                .returns(Integrations::Telemetry.result("Listed.", link: nil, facts: { "comments" => listed }))

    PullRequestReviewRefusalPosting.new(refusal.reload).post!

    assert_equal 1, @posts.size, "the comment the host took is not posted again"
    assert_equal [ Refusal::STATUS_POSTED, "300" ], refusal.reload.values_at(:status, :comment_id)
  end

  test "a comment an approval rule holds was never sent, so its try is not counted and the approved post reads nothing first" do
    review_tools!
    refusal = create_refusal(Refusal::NO_ACCESS)
    approval = pending_approval
    AbilityGateway.stubs(:authorize!).raises(AbilityGateway::PendingApproval.new(approval))

    PullRequestReviewRefusalPosting.new(refusal).post!

    assert_equal Refusal::STATUS_HELD, refusal.reload.status
    assert_nil refusal.attempted_at
  end

  test "tries that run out after one that may have posted leave the comment unconfirmed, still said and never posted again" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    refusal.attempted!
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == CONVERSATION }.raises(answered(502, "GitHub answered 502"))
    Integrations::PullRequestReviews.expects(:call!).with { |_row, called, **| called == COMMENT }.never

    perform_enqueued_jobs { PullRequestReviewRefusalPostJob.perform_later(refusal.id) }

    assert_equal Refusal::STATUS_UNCONFIRMED, refusal.reload.status
    assert refusal.still_said?
    assert_nil Refusal.claim!(@row, signal("r9"), reason: Refusal::NO_ACCESS)
  end

  test "a try that may have posted and is not in the conversation is posted, and a conversation that cannot be read is tried again" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    refusal.attempted!
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == CONVERSATION }.raises(answered(502, "GitHub answered 502"))
    Integrations::PullRequestReviews.expects(:call!).with { |_row, called, **| called == COMMENT }.never

    assert_raises(PullRequestReviewRefusalPosting::Retry) { PullRequestReviewRefusalPosting.new(refusal).post! }

    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == CONVERSATION }.returns([])
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == COMMENT }.returns("301")
    PullRequestReviewRefusalPosting.new(refusal.reload).post!
    assert_equal "301", refusal.reload.comment_id
  end

  test "a comment posted late, after an approval or a retry, is skipped once a review of the pull request started since" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    travel 1.minute
    PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                              trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)
    Integrations::PullRequestReviews.expects(:call!).never

    PullRequestReviewRefusalPosting.new(refusal).post!(approval_id: SecureRandom.uuid)

    assert_equal [ Refusal::STATUS_DROPPED, "A review of the pull request started since." ], refusal.reload.values_at(:status, :dropped_reason)
  end

  test "a comment an approval rule holds is posted once approved, and once declined it is dropped and no longer counts as said" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    approval = pending_approval
    Integrations::PullRequestReviews.stubs(:call!).raises(AbilityGateway::PendingApproval.new(approval))

    PullRequestReviewRefusalPosting.new(refusal).post!

    assert_equal({ "kind" => ApprovalResumption::KIND_PULL_REQUEST_REVIEW_REFUSAL, "refusal_id" => refusal.id }, approval.reload.resume_payload)
    assert_equal [ Refusal::STATUS_HELD, approval.id ], refusal.reload.values_at(:status, :held_approval_id)
    assert_equal ApprovalResumption::RUNS_NOW, ApprovalResumption.approved_words(approval)

    approval.update_columns(status: Ability::Approval::STATUS_APPROVED)
    assert_enqueued_with(job: PullRequestReviewRefusalPostJob, args: [ refusal.id, approval.id ]) { ApprovalResumption.resume!(approval) }

    approval.update_columns(status: Ability::Approval::STATUS_DENIED)
    assert_no_enqueued_jobs(only: PullRequestReviewRefusalPostJob) { ApprovalResumption.decline!(approval) }
    assert_equal Refusal::STATUS_DROPPED, refusal.reload.status
  end

  test "a held comment approved later is posted with that approval" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    approval = pending_approval
    refusal.held!(approval)
    approval.update_columns(status: Ability::Approval::STATUS_APPROVED)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, authorize:, **| called == COMMENT && (@posts << authorize) }.returns("302")
    PullRequestReviewRefusalPosting.any_instance.expects(:authorizer).with(approval.id, attempt: true).returns(->(*) { nil })

    perform_enqueued_jobs { PullRequestReviewRefusalPostJob.perform_later(refusal.id, approval.id) }

    assert_equal [ Refusal::STATUS_POSTED, "302" ], refusal.reload.values_at(:status, :comment_id)
  end

  test "the job tries a temporary failure again and drops the comment once the tries run out" do
    refusal = create_refusal(Refusal::NO_ACCESS)
    Integrations::PullRequestReviews.stubs(:call!).raises(Integrations::Error.new("could not reach api.github.com (Errno::ECONNRESET)").extend(Integrations::Unreachable))

    perform_enqueued_jobs { PullRequestReviewRefusalPostJob.perform_later(refusal.id) }

    assert_equal Refusal::STATUS_DROPPED, refusal.reload.status
    assert_match "Gave up after 5 tries.", refusal.dropped_reason
  end

  test "a connection that cannot post a review, or a reason with nowhere to be told, says nothing and claims nothing" do
    Integrations::PullRequestReviews.stubs(:hosts?).returns(false)
    assert_no_enqueued_jobs(only: PullRequestReviewRefusalPostJob) { PullRequestReviewRefusalPosting.refused!(@row, signal("r1"), reason: Refusal::NO_ACCESS) }

    Integrations::PullRequestReviews.unstub(:hosts?)
    assert_no_enqueued_jobs(only: PullRequestReviewRefusalPostJob) { PullRequestReviewRefusalPosting.refused!(@row, signal("r2"), reason: Refusal::NO_CONNECTION) }
    assert_not Refusal.exists?(workspace: @workspace)
  end

  test "a refusal that was dropped does not silence the next request, and a held one waiting on its approval is reused" do
    first = Refusal.claim!(@row, signal("r1"), reason: Refusal::NO_ACCESS)
    assert_nil Refusal.claim!(@row, signal("r2"), reason: Refusal::NO_ACCESS)

    first.dropped!("The approval was declined.")
    second = Refusal.claim!(@row, signal("r3"), reason: Refusal::NO_ACCESS)
    assert second

    second.held!(pending_approval)
    assert_nil Refusal.claim!(@row, signal("r4", comment: "92"), reason: Refusal::NO_ACCESS), "a comment waits on the approval already asked"
  end

  test "comments asking again with the same reason are answered at most once every ten minutes" do
    assert Refusal.claim!(@row, signal("c1", comment: "91"), reason: Refusal::NO_ACCESS)
    assert_nil Refusal.claim!(@row, signal("c2", comment: "92"), reason: Refusal::NO_ACCESS)
    assert Refusal.claim!(@row, signal("c3", comment: "93"), reason: Refusal::MODEL_NOT_SET_UP), "a new reason is said"

    travel 11.minutes
    assert Refusal.claim!(@row, signal("c4", comment: "94"), reason: Refusal::NO_ACCESS)
  end

  test "a comment's ten minutes and a refusal held on its approval both end once a review of the pull request started since" do
    assert Refusal.claim!(@row, signal("c1", comment: "91"), reason: Refusal::NO_ACCESS)
    held = Refusal.claim!(@row, signal("c2", comment: "92"), reason: Refusal::MODEL_NOT_SET_UP)
    held.held!(pending_approval)
    travel 1.minute
    PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                              trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)
    travel 1.minute

    assert Refusal.claim!(@row, signal("c3", comment: "93"), reason: Refusal::NO_ACCESS)
    assert Refusal.claim!(@row, signal("c4", comment: "94"), reason: Refusal::MODEL_NOT_SET_UP)
  end

  private

  def create_refusal(reason, reference: "acme/api#7:asked:a")
    Refusal.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, reference: reference, reason: reason)
  end

  def signal(reference, comment: nil)
    Signal.new(kind: Integrations::PullRequestReviews::REQUESTED, repository: "acme/api", number: 7, reference: reference, comment: comment)
  end

  # The connection's comment and conversation tools, granted to Halon's review agent, so a call goes through the gateway.
  def review_tools!
    %w[comment_on_pull_request list_pull_request_comments].map do |name|
      tool = @row.integration.tools.create!(name: name, description: name, enabled: true, read_only: name.start_with?("list"))
      Ability::Grant.grant!(workspace: @workspace, principal: SystemAgent.pull_request_review, target: { action: tool.ability_action || tool.sync_ability_action! })
      tool
    end
  end

  def answered(status, message) = Integrations::Error.new(message).tap { |error| error.http_status = status }

  def pending_approval
    Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                              principal_label: "Halon pull request review", action_key: "github.comment_on_pull_request", request_digest: SecureRandom.hex(4), scope: {},
                              params: {}, required_role: WorkspaceMembership.roles[:admin])
  end
end

# Requests that arrive together each take the lock on their own connection, so this runs outside a test's transaction.
class PullRequestReviewRefusalClaimTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "requests at once for the same pull request and reason claim one refusal" do
    workspace = workspaces(:slack_workspace_one)
    integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub claims")
    row = integration.integration_environments.create!(base_config: { "installation_id" => "54321" })
    signals = Array.new(4) do |index|
      Integrations::PullRequestReviews::Signal.new(kind: Integrations::PullRequestReviews::REQUESTED, repository: "acme/claims", number: 7, reference: "claim-#{index}")
    end

    claimed = signals.map do |signal|
      Thread.new { PullRequestReview::Refusal.connection_pool.with_connection { PullRequestReview::Refusal.claim!(row, signal, reason: PullRequestReview::Refusal::NO_ACCESS) } }
    end.map(&:value)

    assert_equal 1, claimed.compact.size
  ensure
    PullRequestReview::Refusal.where(repository: "acme/claims").delete_all
    integration&.destroy!
  end
end
