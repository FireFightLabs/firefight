require "test_helper"

class PullRequestReviewPostingTest < ActiveSupport::TestCase
  REVIEW = Integrations::PullRequestReviews::REVIEW
  COMMENT = Integrations::PullRequestReviews::COMMENT
  EDIT = Integrations::PullRequestReviews::EDIT

  setup do
    @workspace = workspaces(:slack_workspace_one)
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @review = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 7, head_sha: "a" * 40,
                                        trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400, status: PullRequestReview::STATUS_RUNNING)
    @posts = []
  end

  test "the summary comment goes up once as the review starts and is edited after" do
    answer(COMMENT => "100", EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_STARTED)
    posting.run!(PullRequestReview::CHANGE_STARTED)

    assert_equal [ COMMENT, EDIT ], @posts.map(&:first)
    assert_equal "100", @review.reload.summary_comment_id
    assert_includes @posts.first.last[:body], "Reviewing aaaaaaa. Findings appear here as each one is checked."
    assert_no_dashes_or_semicolons(@posts.first.last[:body])
  end

  test "a serious finding gets a comment of its own at once, so people are notified, and the summary lists it" do
    @review.update_columns(summary_comment_id: "100")
    finding = create_finding(serious: true)
    answer(EDIT => "100", COMMENT => "200")

    posting.run!(PullRequestReview::CHANGE_FINDING_ADDED, finding: finding)

    assert_equal [ EDIT, COMMENT ], @posts.map(&:first)
    assert_includes @posts.first.last[:body], "Major, Stability & Availability: Queue the retry for its backoff delay (`app/jobs/retry_job.rb` line 12)"
    assert_includes @posts.last.last[:body], "**Halon found a serious problem in `app/jobs/retry_job.rb` line 12.**"
    assert_equal "200", finding.reload.serious_comment_id
  end

  test "once done, findings on the diff are line comments and the rest sit in the review's body, posted once" do
    @review.update_columns(summary_comment_id: "100")
    on_line = create_finding
    outside = create_finding(claim: "The old migration still runs", position: 2, outside_diff: true, path: "db/migrate/1_old.rb", line: 4)
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    answer(REVIEW => Integrations::PullRequestReviews::Posted.new(reference: "55", comments: [ "701" ]), EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)
    posting.run!(PullRequestReview::CHANGE_FINISHED)

    review = @posts.find { |operation, _| operation == REVIEW }.last
    assert_equal [ "app/jobs/retry_job.rb", 12 ], review[:comments].sole.then { |comment| [ comment.path, comment.line ] }
    assert_includes review[:comments].sole.body, "**Stability & Availability | Major | Quick win**"
    assert_includes review[:comments].sole.body, "<!-- halon-finding: #{on_line.id} -->"
    assert_includes review[:body], "Halon found 2 problems in aaaaaaa, 1 on its line."
    assert_includes review[:body], "### Outside the diff"
    assert_includes review[:body], outside.claim
    assert_includes review[:body], "Instructions for a coding agent"
    assert_equal "a" * 40, review[:commit]
    assert_equal 1, @posts.count { |operation, _| operation == REVIEW }, "the review posts once"
    assert_equal [ "701", "55" ], [ on_line.reload.host_comment_id, @review.reload.review_comment_id ]
  end

  test "a review the host refuses with its line comments goes up with every finding in its body" do
    @review.update_columns(summary_comment_id: "100")
    create_finding
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, operation, **given| operation == EDIT && (@posts << [ operation, given ]) }.returns("100")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, operation, **given| operation == REVIEW && given[:comments].any? && (@posts << [ :refused, given ]) }
                                    .raises(Integrations::PullRequestReviews::Refused, "Line could not be resolved")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, operation, **given| operation == REVIEW && given[:comments].empty? && (@posts << [ operation, given ]) }
                                    .returns(Integrations::PullRequestReviews::Posted.new(reference: "56", comments: []))

    posting.run!(PullRequestReview::CHANGE_FINISHED)

    assert_equal [ :refused, REVIEW, EDIT ], @posts.map(&:first)
    assert_includes @posts.second.last[:body], "### Outside the diff"
  end

  test "a line the host would not place goes up in the conversation, and a review the host took none of is handed back for a retry" do
    @review.update_columns(summary_comment_id: "100")
    placed = create_finding
    unplaced = create_finding(claim: "Bound the queue", position: 2, line: 30)
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    answer(REVIEW => Integrations::PullRequestReviews::Posted.new(reference: "55", comments: [ "701", nil ]), COMMENT => "300", EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)

    comment = @posts.find { |operation, _| operation == COMMENT }.last
    assert_includes comment[:body], "meant for lines the code host would not place a comment on"
    assert_includes comment[:body], unplaced.claim
    assert_equal [ "701", nil ], [ placed.reload.host_comment_id, unplaced.reload.host_comment_id ]

    other = PullRequestReview.create!(workspace: @workspace, integration_environment: @row, repository: "acme/api", number: 8, head_sha: "c" * 40,
                                      trigger: PullRequestReview::TRIGGER_REQUESTED, max_spend_cents: 400, status: PullRequestReview::STATUS_RUNNING)
    other.findings.create!(position: 1, fingerprint: "e" * 32, category: PullRequestReview::Finding::CATEGORY_STABILITY, severity: PullRequestReview::Finding::SEVERITY_MINOR,
                           effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: "Name it", why: "Clearer.", path: "a.rb", line: 1)
    other.finish!(status: PullRequestReview::STATUS_DONE)
    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).returns(nil)

    assert_raises(PullRequestReviewPosting::NotPosted) { PullRequestReviewPosting.new(other.reload).run!(PullRequestReview::CHANGE_FINISHED) }
    assert_nil other.reload.review_posted_at
  end

  test "a failed review says it stopped and never that it found nothing" do
    @review.update_columns(error_summary: PullRequestReview::GAVE_UP, status: PullRequestReview::STATUS_FAILED)

    body = PullRequestReview::Comments.summary(@review.reload, [])

    assert_includes body, "stopped"
    assert_not_includes body, "No problems found."
  end

  test "a finding a push fixed edits its line comment and its own comment to say which commit fixed it" do
    @review.update_columns(summary_comment_id: "100")
    finding = create_finding(serious: true)
    finding.update_columns(host_comment_id: "701", serious_comment_id: "200")
    finding.fixed!("b" * 40)
    answer(EDIT => "x")

    posting.run!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: finding)

    edits = @posts.map(&:last)
    assert_equal [ "100", "701", "200" ], edits.map { |given| given[:reference] }
    assert_equal [ false, true, false ], edits.map { |given| given[:line] || false }
    assert edits.drop(1).all? { |given| given[:body].start_with?("Fixed in bbbbbbb.") }
    assert_includes edits.first[:body], "0 open, 1 fixed."
  end

  test "a rehearsal posts nothing" do
    @review.update_columns(rehearsal: true)
    Integrations::PullRequestReviews.expects(:call!).never

    posting.run!(PullRequestReview::CHANGE_STARTED)
  end

  test "each call is one of the connection's tools, made as Halon's review agent through the gateway and in the activity log" do
    tool = @row.integration.tools.create!(name: "comment_on_pull_request", description: "Comments.", enabled: true, read_only: false)
    Ability::Grant.grant!(workspace: @workspace, principal: SystemAgent.pull_request_review, target: { action: tool.ability_action || tool.sync_ability_action! })
    Integrations::NativeExecutor.expects(:call).returns(Integrations::Telemetry.result("Commented.", link: nil, facts: { "comment_id" => 100 }))

    posting.run!(PullRequestReview::CHANGE_STARTED)

    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: tool.action_key)
    assert_equal [ SystemAgent.pull_request_review.id, AbilityGateway::SOURCE_PULL_REQUEST_REVIEW, Ability::Invocation::OUTCOME_SUCCESS ],
                 [ invocation.principal_id, invocation.source, invocation.outcome ]
    assert_equal "100", @review.reload.summary_comment_id
  end

  private

  def posting = PullRequestReviewPosting.new(@review.reload)

  def answer(replies)
    replies.each do |operation, value|
      Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == operation && (@posts << [ called, given ]) }.returns(value)
    end
  end

  def create_finding(claim: "Queue the retry for its backoff delay", position: 1, **attributes)
    @review.findings.create!(
      position: position, fingerprint: PullRequestReview::Finding.fingerprint_for(path: attributes[:path] || "app/jobs/retry_job.rb", category: "stability", claim: claim),
      category: PullRequestReview::Finding::CATEGORY_STABILITY, severity: PullRequestReview::Finding::SEVERITY_MAJOR,
      effort: PullRequestReview::Finding::EFFORT_QUICK_WIN, claim: claim, why: "It waits five minutes for the sweeper.",
      failure_chain: [ "The retry is queued with no wait", "The sweeper picks it up five minutes later" ],
      evidence: [ { "kind" => PullRequestReview::Finding::EVIDENCE_INCIDENT, "title" => "INC-012", "url" => "https://example.com/inc" } ],
      suggested_fix: "Queue it with its backoff.", agent_instructions: "Pass wait: backoff to perform_later.",
      path: "app/jobs/retry_job.rb", line: 12, **attributes
    )
  end

  def assert_no_dashes_or_semicolons(text)
    assert_no_match(/[—;]/, text.gsub(/<!--.*?-->/, ""))
  end
end
