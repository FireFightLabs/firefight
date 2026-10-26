require "test_helper"

class PullRequestReview::RehearsalTest < ActiveSupport::TestCase
  include PullRequestReviewTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = review_connection(@workspace)
    Integrations::ReviewHost.stubs(:row_for).returns(@row)
    Integrations::CodeReading.stubs(:close)
  end

  test "a rehearsal reviews a pinned commit on the bench's key here and now, unannounced, and gives its findings and what it dropped as data" do
    stub_review_host(@row, [ review_file("app/jobs/charge_job.rb", "@@ -1 +1,2 @@\n x\n+retry\n") ])
    Integrations::ReviewHost.stubs(:sandbox_files).returns([ review_file("app/jobs/charge_job.rb", "@@ -1 +1,2 @@\n x\n+retry\n") ])
    script = lambda do |_number, tools, _part|
      tools.fetch("report_finding").call(**reported(line: 2).symbolize_keys)
      tools.fetch("report_finding").call(**reported(line: 2, claim: "Rename the job").symbolize_keys)
    end
    stub_review_model(ScriptedReviewer.new(script, []), ScriptedVerifier.new([ { verdict: "keep", reason: "Holds." }, { verdict: "drop", reason: "Style." } ]))
    Conversation::BenchKeys.expects(:choice).with(model: "anthropic/claude-sonnet-5.5", provider: "openrouter")
                           .returns(FirefightAi::ModelChoice.new(model: "anthropic/claude-sonnet-5.5", provider: "openrouter"))
    announced = []
    subscriber = ActiveSupport::Notifications.subscribe(PullRequestReview::EVENT) { |event| announced << event.payload[:change] }

    review = PullRequestReview::Rehearsal.run!(workspace: @workspace, repository: "acme/api", number: 7, head_sha: "e" * 40, base_sha: "f" * 40,
                                               model: "anthropic/claude-sonnet-5.5", provider: "openrouter", max_spend_cents: 2_500)
    data = PullRequestReview::Rehearsal.to_h(review)

    assert review.rehearsal?
    assert_empty announced
    assert_equal [ "done", "e" * 40, "f" * 40, "anthropic/claude-sonnet-5.5" ], data.values_at("status", "head_sha", "base_sha", "model")
    assert_equal [ "Queue the retry for its backoff delay" ], data["findings"].map { |finding| finding["claim"] }
    assert_equal [ { "claim" => "Rename the job", "path" => "app/jobs/charge_job.rb", "reason" => "Style." } ], data["dropped"]
    assert_equal 2_500, review.max_spend_cents
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "a rehearsal that fails ends failed with a plain sentence rather than raising" do
    Integrations::ReviewHost.stubs(:pull_request).returns(review_pull)
    PullRequestReview::Runner.any_instance.stubs(:run).raises(Integrations::Error, "GitHub answered 502")

    review = PullRequestReview::Rehearsal.run!(workspace: @workspace, repository: "acme/api", number: 7, max_spend_cents: 100)

    assert_equal [ PullRequestReview::STATUS_FAILED, PullRequestReview::COULD_NOT_READ ], [ review.status, review.error_summary ]
  end
end
