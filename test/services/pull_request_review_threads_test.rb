require "test_helper"

class PullRequestReviewThreadsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400, status: PullRequestReview::STATUS_DONE)
    @finding = @review.findings.create!(position: 1, fingerprint: "f" * 32, category: PullRequestReview::Finding::CATEGORY_STABILITY,
                                        severity: PullRequestReview::Finding::SEVERITY_MAJOR, effort: PullRequestReview::Finding::EFFORT_QUICK_WIN,
                                        claim: "Queue the retry for its backoff delay", why: "It waits five minutes.", path: "app/jobs/retry_job.rb", line: 12,
                                        host_comment_id: "701")
    @said = []
    PullRequestReviewPosting.any_instance.stubs(:changes).returns("diff --git a/app/jobs/retry_job.rb b/app/jobs/retry_job.rb\n+ wait: backoff")
    PullRequestReviewPosting.any_instance.stubs(:file).returns("12  RetryJob.set(wait: backoff).perform_later")
    PullRequestReviewPosting.any_instance.stubs(:reply!).with { |_finding, body| @said << [ :reply, body ] }
    PullRequestReviewPosting.any_instance.stubs(:resolve!).with { |_finding| @said << [ :resolve ] }
  end

  test "a push that fixed a finding says so on its thread, resolves it and marks it fixed in that commit, once" do
    FirefightAi::ReviewThread.any_instance.expects(:recheck).once.returns(FirefightAi::ReviewThread::Recheck.new(outcome: "fixed", words: "The job now waits for its backoff"))

    threads.recheck!("a" * 40, "b" * 40)
    threads.recheck!("a" * 40, "b" * 40)

    assert_equal [ [ :reply, "Fixed in bbbbbbb. The job now waits for its backoff." ], [ :resolve ] ], @said
    assert_equal [ PullRequestReview::Finding::STATUS_FIXED, "b" * 40 ], @finding.reload.values_at(:status, :fixed_in_sha)
  end

  test "a push that did not fix it says so and leaves the thread open" do
    FirefightAi::ReviewThread.any_instance.stubs(:recheck).returns(FirefightAi::ReviewThread::Recheck.new(outcome: "not_fixed", words: "It still queues with no wait"))

    threads.recheck!("a" * 40, "b" * 40)

    assert_equal [ [ :reply, "Not fixed yet in bbbbbbb. It still queues with no wait." ] ], @said
    assert @finding.reload.open?
  end

  test "a push that did not touch the finding's file says nothing" do
    PullRequestReviewPosting.any_instance.stubs(:changes).returns("diff --git a/README.md b/README.md")
    FirefightAi::ReviewThread.any_instance.expects(:recheck).never

    threads.recheck!("a" * 40, "b" * 40)

    assert_empty @said
  end

  test "a reply that shows the finding wrong withdraws it, says so and resolves the thread, and the same reply is answered once" do
    FirefightAi::ReviewThread.any_instance.expects(:answer).once
                         .returns(FirefightAi::ReviewThread::Answer.new(answer: "You are right, the job sets its wait.", withdraw: true, reason: "The job already waits for its backoff."))
    reply = Integrations::PullRequestReviews::Signal.new(kind: Integrations::PullRequestReviews::COMMENTED, repository: "acme/api", number: 7, reference: "r",
                                                         comment: "88", thread: "701", body: "RetryJob sets wait itself", author: "ada")

    threads.answer!(reply)
    threads.answer!(reply)

    assert_equal :reply, @said.first.first
    assert_includes @said.first.last, "My finding was wrong, and I withdraw it. The job already waits for its backoff."
    assert_equal [ :resolve ], @said.last
    assert_equal "The job already waits for its backoff.", @finding.reload.withdrawn_reason
  end

  test "a reply that does not show the finding wrong is answered and the finding stands" do
    FirefightAi::ReviewThread.any_instance.stubs(:answer).returns(FirefightAi::ReviewThread::Answer.new(answer: "It still queues with no wait on line 12.", withdraw: false, reason: ""))
    reply = Integrations::PullRequestReviews::Signal.new(kind: Integrations::PullRequestReviews::COMMENTED, repository: "acme/api", number: 7, reference: "r",
                                                         comment: "89", thread: "701", body: "Is this real?", author: "ada")

    threads.answer!(reply)

    assert_equal [ [ :reply, "It still queues with no wait on line 12." ] ], @said
    assert @finding.reload.open?
  end

  private

  def threads = PullRequestReviewThreads.new(@finding.reload)
end
