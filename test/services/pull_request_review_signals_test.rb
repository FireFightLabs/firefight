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

  private

  def signal(kind, **given)
    Signal.new(kind: kind, repository: "acme/api", number: 7, reference: SecureRandom.hex(4), head_sha: "a" * 40, author: "ada", **given)
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
