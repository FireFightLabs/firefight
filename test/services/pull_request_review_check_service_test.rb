require "test_helper"

class PullRequestReviewCheckServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = @integration.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400)
    @lesson = Chat::Memory.create!(workspace: @workspace, text: "Checkout retries go up when the payment timeout changes", source: incidents(:active_critical_ws1),
                                   state: Chat::Memory::STATE_UNCONFIRMED).tap { |memory| memory.approve!(by: @admin, strict: true) }
  end

  test "a held review sets a failing check once, linking to the Lessons tab, and passes it once overridden" do
    held = finding
    AppUrl.stubs(:options).returns(host: "firefight.test", protocol: "https")
    sent = []
    Integrations::ReviewChecks.stubs(:set!).with { |row, repository:, sha:, check:| row == @row && repository == "acme/api" && sha == "a" * 40 && (sent << check) }

    assert_equal PullRequestReview::CHECK_FAILING, service.update!
    assert_nil service.update!, "the same state on the same commit is set once"
    held.override!(by: @admin, reason: "Behind a flag")
    assert_equal PullRequestReview::CHECK_PASSING, service.update!

    assert_equal [ Integrations::ReviewChecks::FAILING, Integrations::ReviewChecks::PASSING ], sent.map(&:state)
    assert_equal "https://firefight.test/app/memory?review=#{@review.id}&tab=lessons", sent.first.url
  end

  test "a host that refuses keeps why on the review and tries again at the next change" do
    finding
    Integrations::ReviewChecks.stubs(:set!).raises(Integrations::Error, "GitHub answered 403")

    assert_nil service.update!
    assert_equal "GitHub answered 403", @review.reload.check_error
    assert_nil @review.check_state
  end

  test "nothing is set for a review no strict lesson touched or a rehearsal" do
    Integrations::ReviewChecks.expects(:set!).never

    assert_nil service.update!
    finding
    @review.update!(rehearsal: true)
    assert_nil service.update!
  end

  test "a finding written or a lesson changed works the check out again in a job" do
    assert_enqueued_with(job: PullRequestReviewCheckJob, args: [ @review.id ]) { finding }
    assert_enqueued_with(job: PullRequestReviewCheckJob, args: [ @review.id ]) { @lesson.turn_down!(by: @admin) }
  end

  private

  def service = PullRequestReviewCheckService.new(@review.reload)

  def finding
    @review.findings.create!(
      position: @review.next_position, fingerprint: SecureRandom.hex(16), category: PullRequestReview::Finding::CATEGORY_STABILITY,
      severity: PullRequestReview::Finding::SEVERITY_MAJOR, effort: PullRequestReview::Finding::EFFORT_QUICK_WIN,
      claim: "Raises the payment timeout", why: "Retries go up.", path: "app/a.rb", line: 3, lesson: @lesson
    )
  end
end
