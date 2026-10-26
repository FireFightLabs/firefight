require "test_helper"

class PullRequestReview::RunnerTest < ActiveSupport::TestCase
  include PullRequestReviewTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @row = review_connection(@workspace)
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: REVIEW_HEAD,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400)
    @review.claim!(by: "job-1")
    @files = [
      review_file("app/jobs/charge_job.rb", "@@ -1,2 +1,4 @@\n def perform\n+  retry_charge\n+  log\n end\n"),
      review_file("db/migrate/1_add_index.rb", "@@ -0,0 +1 @@\n+add_index :orders, :state\n"),
      review_file("README.md", "@@ -1 +1 @@\n-a\n+b\n")
    ]
    stub_review_host(@row, @files, paths: @files.map(&:path) + [ "app/models/order.rb" ])
  end

  test "every file is reviewed, migrations first, each reported finding is checked and written as it holds, and the review says what it does and its risk" do
    reviewer = ScriptedReviewer.new(->(_number, tools, _part) { tools.fetch("report_finding").call(**reported.symbolize_keys) }, [])
    verifier = ScriptedVerifier.new([ { verdict: "keep", reason: "Line 3 retries at once.", corrections: { "severity" => "critical", "serious" => true } } ])
    stub_review_model(reviewer, verifier)

    result = PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_equal PullRequestReview::STATUS_DONE, result.status
    assert_equal [ "db/migrate/1_add_index.rb", "app/jobs/charge_job.rb", "README.md" ], reviewer.parts_seen.sole[1], "a migration is read before the code, and docs last"
    @review.reload
    assert_equal [ "Retries a failed charge.", "high", "It can charge twice." ], [ @review.summary, @review.risk, @review.risk_reason ]
    assert_equal @files.map(&:path).sort, @review.reviewed_paths.sort
    assert_equal [ "Retry checkout", "https://github.com/acme/api/pull/7", REVIEW_BASE, "claude-sonnet-4-5" ], [ @review.title, @review.url, @review.base_sha, @review.model ]

    finding = @review.findings.sole
    assert_equal [ 1, PullRequestReview::Finding::SEVERITY_CRITICAL, true, false ], [ finding.position, finding.severity, finding.serious, finding.outside_diff ]
    assert_equal [ { "kind" => "code", "title" => "The retry", "url" => "https://github.com/acme/api/blob/#{REVIEW_HEAD}/app/jobs/charge_job.rb#L3" } ], finding.evidence
    assert_equal [ "A charge fails", "The retry runs at once and fails again" ], finding.failure_chain
    check = @review.checks.sole
    assert_equal [ PullRequestReview::Check::VERDICT_KEPT, finding, "Line 3 retries at once." ], [ check.verdict, check.finding, check.reason ]
    assert_includes verifier.asked.sole[:context], "The pull request's diff of app/jobs/charge_job.rb"
    assert_operator @review.spent_micros, :>=, 15_000, "what the check spent counts against the review too"

    overview = reviewer.opened
    assert_includes overview["The pull request"], "<tool_result tool=\"pull_request_description\" trust=\"untrusted\">\nRetries a failed charge."
    assert_includes overview["Its files"], "- db/migrate/1_add_index.rb (modified, +1 -0) part 1"
    assert_includes overview["Reading its code"], "The head is #{REVIEW_HEAD} in acme/api, and the base is #{REVIEW_BASE}"
    assert_equal "The resource map does not hold acme/api, so where it runs is not known.", overview["Where this repository runs"]
  end

  test "a later finding's check withdraws an earlier one, and a dropped report is never written but its check says why" do
    script = lambda do |_number, tools, _part|
      tools.fetch("report_finding").call(**reported.symbolize_keys)
      tools.fetch("report_finding").call(**reported(path: "db/migrate/1_add_index.rb", line: 1, claim: "Add the index concurrently").symbolize_keys)
      tools.fetch("report_finding").call(**reported(path: "README.md", line: 1, claim: "Fix the typo").symbolize_keys)
    end
    verifier = ScriptedVerifier.new([
      { verdict: "keep", reason: "It retries at once." },
      { verdict: "keep", reason: "orders has 40 million rows.", earlier: [ { "finding" => 1, "outcome" => "withdraw", "note" => "The job already waits in its retry_on." } ] },
      { verdict: "drop", reason: "Not a problem with this change." }
    ])
    stub_review_model(ScriptedReviewer.new(script, []), verifier)

    PullRequestReview::Runner.new(@review, by: "job-1").run

    first, second = @review.findings.reload.to_a
    assert_equal [ PullRequestReview::Finding::STATUS_WITHDRAWN, "The job already waits in its retry_on." ], [ first.status, first.withdrawn_reason ]
    assert_equal second.id, first.cross_checks.sole["finding_id"]
    assert_equal PullRequestReview::Finding::STATUS_OPEN, second.status
    assert_equal 2, @review.findings.count
    dropped = @review.checks.find_by!(verdict: PullRequestReview::Check::VERDICT_DROPPED)
    assert_equal [ "Fix the typo", "Not a problem with this change." ], [ dropped.claim, dropped.reason ]
    assert_includes verifier.asked.second[:earlier], "1. Stability & Availability | Major | Quick win, app/jobs/charge_job.rb:3"
  end

  test "a report of a finding already withdrawn is not checked again, and the reviewer is told why it was withdrawn" do
    answers = []
    script = lambda do |_number, tools, _part|
      answers << tools.fetch("report_finding").call(**reported.symbolize_keys)
      @review.findings.sole.withdraw!("The job already waits in its retry_on.")
      answers << tools.fetch("report_finding").call(**reported.symbolize_keys)
    end
    stub_review_model(ScriptedReviewer.new(script, []), ScriptedVerifier.new([ { verdict: "keep", reason: "Holds." } ]))

    PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_equal "Not written again. It is finding 1, which was withdrawn: The job already waits in its retry_on.", answers.second
    assert_equal 1, @review.checks.count
  end

  test "a report whose evidence points at nothing Firefight can open is refused with why, and the reviewer can fix it" do
    answers = []
    script = lambda do |_number, tools, _part|
      answers << tools.fetch("report_finding").call(**reported(evidence: [ { "kind" => "incident", "reference" => "INC-999", "title" => "Old outage" },
                                                                          { "kind" => "metric", "reference" => "https://grafana.example.com/d/1", "title" => "Retries" } ]).symbolize_keys)
      answers << tools.fetch("report_finding").call(**reported(path: "app/nowhere.rb").symbolize_keys)
    end
    stub_review_model(ScriptedReviewer.new(script, []), ScriptedVerifier.new([]))

    PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_match "No evidence resolved. The incident evidence \"INC-999\" points at nothing Firefight can open.", answers.first
    assert_match "The metric evidence \"https://grafana.example.com/d/1\" points at nothing", answers.first, "a link no result gave is not evidence"
    assert_match "There is no file app/nowhere.rb at the pull request's head or in its diff.", answers.second
    assert_empty @review.findings
    assert_empty @review.checks
  end

  test "a finding on an incident, its postmortem and a line outside the diff links each, and the line is marked outside the diff" do
    incident = incidents(:resolved_minor_ws1)
    evidence = [ { "kind" => "incident", "reference" => incident.identifier.downcase, "title" => "Retries took checkout down" },
                 { "kind" => "postmortem", "reference" => incident.identifier, "title" => "Why" },
                 { "kind" => "code", "reference" => "app/models/order.rb", "title" => "Order" } ]
    script = ->(_number, tools, _part) { tools.fetch("report_finding").call(**reported(path: "app/models/order.rb", line: 40, evidence: evidence).symbolize_keys) }
    stub_review_model(ScriptedReviewer.new(script, []), ScriptedVerifier.new([ { verdict: "keep", reason: "Holds." } ]))

    PullRequestReview::Runner.new(@review, by: "job-1").run

    finding = @review.findings.sole
    assert finding.outside_diff
    routes = Rails.application.routes.url_helpers
    assert_equal [ routes.incident_path(incident), routes.incident_postmortem_path(incident), "https://github.com/acme/api/blob/#{REVIEW_HEAD}/app/models/order.rb" ],
                 finding.evidence.map { |item| item["url"] }
  end

  test "a file that may hold secrets is left out, and a finding on it reaches its check without its diff" do
    secret = review_file("config/credentials.yml", "@@ -1 +1 @@\n-token: old\n+token: sk_live_123\n")
    stub_review_host(@row, @files + [ secret ])
    script = ->(_number, tools, _part) { tools.fetch("report_finding").call(**reported(path: "config/credentials.yml", line: 1, evidence: [ { "kind" => "code", "reference" => "app/jobs/charge_job.rb:3", "title" => "x" } ]).symbolize_keys) }
    verifier = ScriptedVerifier.new([ { verdict: "drop", reason: "No." } ])
    stub_review_model(ScriptedReviewer.new(script, []), verifier)

    PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_includes @review.reload.left_out, { "path" => "config/credentials.yml", "reason" => Integrations::ReviewHost::LEFT_OUT_SECRETS }
    context = verifier.asked.sole[:context]
    assert_includes context, "The pull request changes config/credentials.yml, but its diff is left out of the review."
    assert_not_includes context, "sk_live_123"
  end

  test "a review whose spending limit runs out leaves the files it did not reach out with why, and still concludes" do
    big = "@@ -1,1 +1,550 @@\n#{(1..550).map { |line| "+    line #{line} #{'x' * 40}\n" }.join}"
    files = [ review_file("app/a.rb", big), review_file("app/b.rb", big) ]
    stub_review_host(@row, files)
    reviewer = ScriptedReviewer.new(->(*) { }, [ FirefightAi::AgentLoop::STATUS_ANSWERED, FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET ])
    stub_review_model(reviewer, ScriptedVerifier.new([]))

    result = PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_equal PullRequestReview::STATUS_DONE, result.status
    assert_equal [ [ "app/a.rb" ], [ "app/b.rb" ] ], reviewer.parts_seen.map(&:second)
    assert_equal [ "app/a.rb" ], @review.reload.reviewed_paths
    assert_includes @review.left_out, { "path" => "app/b.rb", "reason" => PullRequestReview::Runner::BUDGET_SPENT }
    assert_equal FirefightAi::PullRequestReviewer::TURNS_PER_PART, reviewer.parts_seen.first[2], "the turns each part may use are counted from what the review used before it"
    assert_equal 3 + FirefightAi::PullRequestReviewer::TURNS_PER_PART, reviewer.parts_seen.second[2]
  end

  test "a retried review carries on from the parts it already reviewed" do
    @review.update!(reviewed_paths: @files.map(&:path))
    reviewer = ScriptedReviewer.new(->(*) { }, [])
    stub_review_model(reviewer, ScriptedVerifier.new([]))

    PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_empty reviewer.parts_seen
  end

  test "a rehearsal of an earlier commit reads its files from the sandbox against the base it names" do
    @review.update!(head_sha: "e" * 40, base_sha: "f" * 40)
    Integrations::ReviewHost.expects(:changed_files).never
    Integrations::ReviewHost.expects(:sandbox_files).with(@row, anything, base_sha: "f" * 40, key: @review.code_box_key).returns(@files)
    stub_review_model(ScriptedReviewer.new(->(*) { }, []), ScriptedVerifier.new([]))

    PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_equal "f" * 40, @review.reload.base_sha
  end

  test "a review whose connection is gone fails with why" do
    @review.update!(integration_environment: nil)

    result = PullRequestReview::Runner.new(@review, by: "job-1").run

    assert_equal [ PullRequestReview::STATUS_FAILED, PullRequestReview::NO_CONNECTION ], [ result.status, result.error_summary ]
  end
end
