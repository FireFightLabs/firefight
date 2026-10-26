require "test_helper"

class PullRequestReviewJobTest < ActiveJob::TestCase
  include PullRequestReviewTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = review_connection(@workspace)
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: REVIEW_HEAD,
                                        trigger: PullRequestReview::TRIGGER_AUTOMATIC, max_spend_cents: 400)
    stub_review_host(@row, [ review_file("app/jobs/charge_job.rb", "@@ -1 +1,2 @@\n x\n+retry\n") ])
    Integrations::CodeReading.stubs(:close)
  end

  test "a review runs on its own, announcing that it started, each finding as it is written, and that it finished, and closes its sandbox" do
    script = ->(_number, tools, _part) { tools.fetch("report_finding").call(**reported(line: 2).symbolize_keys) }
    stub_review_model(ScriptedReviewer.new(script, []), ScriptedVerifier.new([ { verdict: "keep", reason: "Holds." } ]))
    Integrations::CodeReading.expects(:close).with(@review.code_box_key)
    announced = []
    subscriber = ActiveSupport::Notifications.subscribe(PullRequestReview::EVENT) { |event| announced << event.payload[:change] }

    PullRequestReviewJob.perform_now(@review.id)

    assert_equal PullRequestReview::STATUS_DONE, @review.reload.status
    assert_equal [ PullRequestReview::CHANGE_STARTED, PullRequestReview::CHANGE_FINDING_ADDED, PullRequestReview::CHANGE_FINISHED ], announced
    assert_not_nil @review.finished_at
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "a review another worker holds is left to it" do
    @review.claim!(by: "other-job")
    PullRequestReview::Runner.expects(:new).never

    PullRequestReviewJob.perform_now(@review.id)
  end

  test "a review nobody can pay for fails at once with a plain sentence" do
    PullRequestReview::Runner.any_instance.stubs(:run).raises(FirefightAi::OutOfCredit, "No AI account can pay for this call.")

    PullRequestReviewJob.perform_now(@review.id)

    assert_equal [ PullRequestReview::STATUS_FAILED, PullRequestReview::OUT_OF_CREDIT ], @review.reload.values_at(:status, :error_summary)
  end

  test "an error hands the review back for the retry, and the last retry fails it with what stopped it" do
    PullRequestReview::Runner.any_instance.stubs(:run).raises(Integrations::Error, "GitHub answered 502")

    perform_enqueued_jobs { PullRequestReviewJob.perform_later(@review.id) }

    assert_equal [ PullRequestReview::STATUS_FAILED, PullRequestReview::COULD_NOT_READ ], @review.reload.values_at(:status, :error_summary)
    assert_equal 3, @review.attempts
  end

  test "a review whose worker keeps dying is given up" do
    @review.update_columns(attempts: PullRequestReview::MAX_ATTEMPTS)
    PullRequestReview::Runner.expects(:new).never

    PullRequestReviewJob.perform_now(@review.id)

    assert_equal [ PullRequestReview::STATUS_FAILED, PullRequestReview::TOO_MANY_ATTEMPTS ], @review.reload.values_at(:status, :error_summary)
  end
end
