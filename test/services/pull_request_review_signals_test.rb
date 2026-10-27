require "test_helper"

class PullRequestReviewSignalsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  Signal = Integrations::PullRequestReviews::Signal

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    Integrations::GithubApp.stubs(:bot_login).returns("firefight-app[bot]")
    @signals = PullRequestReviewSignals.new(@row)
  end

  test "Firefight added as a reviewer starts a review of the head, and someone else added starts nothing" do
    expect_start(PullRequestReview::TRIGGER_REQUESTED)
    @signals.receive!(signal(Integrations::PullRequestReviews::REQUESTED, reviewers: [ "firefight-app[bot]" ]))

    PullRequestReview::Start.expects(:call).never
    @signals.receive!(signal(Integrations::PullRequestReviews::REQUESTED, reviewers: [ "ada" ]))
  end

  test "a pull request that opens is reviewed only where the workspace reviews every pull request, and never while a draft" do
    PullRequestReview::Start.expects(:call).never
    @signals.receive!(signal(Integrations::PullRequestReviews::OPENED))

    @workspace.update!(pull_request_reviews_on_open: Workspace::PullRequestReviewing::ON_OPEN_CHOSEN, pull_request_review_repositories: [ "acme/api" ])
    @signals = PullRequestReviewSignals.new(@row.reload)
    @signals.receive!(signal(Integrations::PullRequestReviews::OPENED, draft: true))

    PullRequestReview::Start.unstub(:call)
    expect_start(PullRequestReview::TRIGGER_AUTOMATIC)
    @signals.receive!(signal(Integrations::PullRequestReviews::OPENED))
  end

  test "a push to a reviewed pull request reviews the new head the same way and checks each open thread's fix" do
    review = create_review(status: PullRequestReview::STATUS_DONE)
    finding = create_finding(review, host_comment_id: "701")
    expect_start(PullRequestReview::TRIGGER_REQUESTED)

    assert_enqueued_with(job: PullRequestReviewRecheckJob, args: [ finding.id, "a" * 40, "b" * 40 ]) do
      @signals.receive!(signal(Integrations::PullRequestReviews::PUSHED, head_sha: "b" * 40))
    end
  end

  test "a push while the last review still runs is tried again once it ends" do
    create_review(status: PullRequestReview::STATUS_DONE)
    PullRequestReview::Start.stubs(:call).returns(create_review(head_sha: "c" * 40, number: 7, status: PullRequestReview::STATUS_RUNNING))

    assert_enqueued_with(job: PullRequestReviewSignalJob) do
      @signals.receive!(signal(Integrations::PullRequestReviews::PUSHED, head_sha: "b" * 40))
    end
  end

  test "a merge is recorded on every review of the pull request" do
    review = create_review(status: PullRequestReview::STATUS_DONE)

    @signals.receive!(signal(Integrations::PullRequestReviews::MERGED))

    assert review.reload.merged_at
  end

  test "a pull request Halon opened that merged or closed is read for a lesson, and anyone else's is not" do
    session = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "m", repository: "acme/api", budget_micros: 1,
                                       expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, pull_request_number: 7)

    assert_enqueued_with(job: PullRequestLessonJob, args: [ session.id ]) { @signals.receive!(signal(Integrations::PullRequestReviews::MERGED)) }
    assert_enqueued_with(job: PullRequestLessonJob, args: [ session.id ]) { @signals.receive!(signal(Integrations::PullRequestReviews::CLOSED)) }
    assert_no_enqueued_jobs(only: PullRequestLessonJob) { @signals.receive!(signal(Integrations::PullRequestReviews::CLOSED, number: 8)) }
  end

  test "a person's reply on one of Halon's threads is answered, and Halon's own and a bot's are not" do
    review = create_review(status: PullRequestReview::STATUS_DONE)
    finding = create_finding(review, host_comment_id: "701")

    assert_enqueued_with(job: PullRequestReviewAnswerJob) do
      @signals.receive!(signal(Integrations::PullRequestReviews::COMMENTED, comment: "88", thread: "701", body: "The job already waits", author: "ada"))
    end
    assert_equal finding.id, enqueued_jobs.last["arguments"].first

    assert_no_enqueued_jobs(only: PullRequestReviewAnswerJob) do
      @signals.receive!(signal(Integrations::PullRequestReviews::COMMENTED, comment: "89", thread: "701", body: "Fixed in abc.", author: "firefight-app[bot]"))
      @signals.receive!(signal(Integrations::PullRequestReviews::COMMENTED, comment: "90", thread: "701", body: "Bump", author: "dependabot[bot]", person: false))
      @signals.receive!(signal(Integrations::PullRequestReviews::COMMENTED, comment: "91", thread: "999", body: "Elsewhere", author: "ada"))
    end
  end

  test "a reply to Halon's own answer, as a host that names the parent comment sends it, is answered too" do
    review = create_review(status: PullRequestReview::STATUS_DONE)
    finding = create_finding(review, host_comment_id: "701")
    finding.said!(comment: "702", author: SystemAgent::HALON, body: "Not fixed yet.", halon: true)

    assert_enqueued_with(job: PullRequestReviewAnswerJob) do
      @signals.receive!(signal(Integrations::PullRequestReviews::COMMENTED, comment: "703", thread: "702", body: "Now?", author: "ada"))
    end
  end

  test "a comment asking Halon to review starts one" do
    expect_start(PullRequestReview::TRIGGER_REQUESTED)

    @signals.receive!(signal(Integrations::PullRequestReviews::COMMENTED, comment: "92", body: "@firefight review please", author: "ada"))
  end

  test "a head Halon already reviewed is not reviewed again, and a refusal to start is logged, not raised" do
    create_review(status: PullRequestReview::STATUS_DONE)
    PullRequestReview::Start.expects(:call).never
    @signals.receive!(signal(Integrations::PullRequestReviews::REQUESTED, reviewers: [ "firefight-app[bot]" ]))

    PullRequestReview::Start.unstub(:call)
    PullRequestReview::Start.stubs(:call).raises(PullRequestReview::Start::Refused, "Halon is not available")
    assert_nothing_raised { @signals.receive!(signal(Integrations::PullRequestReviews::REQUESTED, head_sha: "d" * 40, reviewers: [ "firefight-app[bot]" ])) }
  end

  test "a review a person asked for that cannot start says why on the pull request, and a request delivered again says nothing more" do
    PullRequestReview::Start.stubs(:call).raises(PullRequestReview::Start::Refused.new("Halon has no access to read GitHub.", reason: PullRequestReview::Refusal::NO_ACCESS))
    commented = signal(Integrations::PullRequestReviews::COMMENTED, comment: "92", body: "@firefight review please", reference: "acme/api#7:comment:92")
    asked = signal(Integrations::PullRequestReviews::REQUESTED, reviewers: [ "firefight-app[bot]" ], number: 8, reference: "acme/api#8:asked:a")

    assert_enqueued_jobs 2, only: PullRequestReviewRefusalPostJob do
      2.times { @signals.receive!(commented) }
      2.times { @signals.receive!(asked) }
    end

    refusals = PullRequestReview::Refusal.where(workspace: @workspace)
    assert_equal [ "acme/api#7:comment:92", "acme/api#8:asked:a" ], refusals.order(:reference).pluck(:reference)
    assert refusals.all? { |refusal| refusal.reason == PullRequestReview::Refusal::NO_ACCESS && refusal.integration_environment == @row }
  end

  test "a host that asks again at each push hears a refusal once per pull request and reason, and again once a review ran since" do
    no_access = PullRequestReview::Start::Refused.new("Halon has no access to read GitHub.", reason: PullRequestReview::Refusal::NO_ACCESS)
    not_set_up = PullRequestReview::Start::Refused.new(Investigation::MODEL_NOT_SET_UP, reason: PullRequestReview::Refusal::MODEL_NOT_SET_UP)
    asked = ->(head) { signal(Integrations::PullRequestReviews::REQUESTED, reviewers: [ "firefight-app[bot]" ], head_sha: head, reference: "acme/api#7:asked:#{head}") }

    PullRequestReview::Start.stubs(:call).raises(no_access)
    assert_enqueued_jobs 1, only: PullRequestReviewRefusalPostJob do
      @signals.receive!(asked.call("a" * 40))
      travel 1.minute
      @signals.receive!(asked.call("b" * 40))
    end

    travel 1.minute
    PullRequestReview::Start.unstub(:call)
    PullRequestReview::Start.stubs(:call).raises(not_set_up)
    assert_enqueued_jobs 1, only: PullRequestReviewRefusalPostJob do
      @signals.receive!(asked.call("c" * 40))
    end

    travel 1.minute
    create_review(status: PullRequestReview::STATUS_DONE, head_sha: "d" * 40)
    travel 1.minute
    PullRequestReview::Start.unstub(:call)
    PullRequestReview::Start.stubs(:call).raises(no_access)
    assert_enqueued_jobs 1, only: PullRequestReviewRefusalPostJob do
      @signals.receive!(asked.call("e" * 40))
      travel 1.minute
      @signals.receive!(asked.call("f" * 40))
    end
    assert_enqueued_jobs 1, only: PullRequestReviewRefusalPostJob do
      @signals.receive!(signal(Integrations::PullRequestReviews::REQUESTED, reviewers: [ "firefight-app[bot]" ], number: 8, reference: "acme/api#8:asked:a"))
    end
  end

  test "a review nobody asked for that cannot start says nothing on the pull request" do
    @workspace.update!(pull_request_reviews_on_open: Workspace::PullRequestReviewing::ON_OPEN_CHOSEN, pull_request_review_repositories: [ "acme/api" ])
    @signals = PullRequestReviewSignals.new(@row.reload)
    create_review(status: PullRequestReview::STATUS_DONE, head_sha: "c" * 40)
    PullRequestReview::Start.stubs(:call).raises(PullRequestReview::Start::Refused.new("Halon has no access to read GitHub.", reason: PullRequestReview::Refusal::NO_ACCESS))

    assert_no_enqueued_jobs(only: PullRequestReviewRefusalPostJob) do
      @signals.receive!(signal(Integrations::PullRequestReviews::OPENED))
      @signals.receive!(signal(Integrations::PullRequestReviews::PUSHED, head_sha: "b" * 40))
      PullRequestReviewSignals.opened_by_halon!(@row, repository: "acme/api", number: 7)
    end
  end

  private

  def signal(kind, **given)
    Signal.new(**{ kind: kind, repository: "acme/api", number: 7, reference: SecureRandom.hex(4), head_sha: "a" * 40, author: "ada" }.merge(given))
  end

  def expect_start(trigger)
    PullRequestReview::Start.expects(:call).with(workspace: @workspace, repository: "acme/api", number: 7, trigger: trigger, row: @row)
                            .returns(PullRequestReview.new(status: PullRequestReview::STATUS_QUEUED, head_sha: "a" * 40))
  end

  def create_review(**attributes)
    PullRequestReview.create!({ workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400 }.merge(attributes))
  end

  def create_finding(review, **attributes)
    review.findings.create!(position: 1, fingerprint: "f" * 32, category: PullRequestReview::Finding::CATEGORY_STABILITY,
                            severity: PullRequestReview::Finding::SEVERITY_MAJOR, effort: PullRequestReview::Finding::EFFORT_QUICK_WIN,
                            claim: "Queue the retry for its backoff delay", why: "It waits five minutes.", path: "app/jobs/retry_job.rb", line: 12, **attributes)
  end
end
