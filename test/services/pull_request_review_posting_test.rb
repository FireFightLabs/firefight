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
    Integrations::PullRequestReviews.stubs(:public?).returns(false)
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
    answer(REVIEW => Integrations::PullRequestReviews::Posted.new(reference: "55", comments: [ "701" ], urls: [ "https://example.com/c701" ], url: "https://example.com/r55"),
           EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)
    posting.run!(PullRequestReview::CHANGE_FINISHED)

    review = @posts.find { |operation, _| operation == REVIEW }.last
    assert_equal [ "app/jobs/retry_job.rb", 12 ], review[:comments].sole.then { |comment| [ comment.path, comment.line ] }
    assert_includes review[:comments].sole.body, "**Stability & Availability | Major | Quick win**"
    assert_includes review[:comments].sole.body, "<!-- halon-finding: #{on_line.id} -->"
    assert_includes review[:body], "Halon found 2 problems in aaaaaaa, 1 on its line."
    assert_includes review[:body], "### Not on a line"
    assert_includes review[:body], outside.claim
    assert_includes review[:body], "Instructions for a coding agent"
    assert_equal "a" * 40, review[:commit]
    assert_equal 1, @posts.count { |operation, _| operation == REVIEW }, "the review posts once"
    assert_equal [ "701", "55" ], [ on_line.reload.host_comment_id, @review.reload.review_comment_id ]
    assert_equal [ "https://example.com/c701", "https://example.com/r55" ], [ on_line.host_comment_url, outside.reload.host_comment_url ]
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
    assert_includes @posts.second.last[:body], "### Not on a line"
  end

  test "a review the host took none of is handed back for a retry" do
    create_finding
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    Integrations::PullRequestReviews.stubs(:call!).returns(nil)

    assert_raises(PullRequestReviewPosting::NotPosted) { posting.run!(PullRequestReview::CHANGE_FINISHED) }
    assert_nil @review.reload.review_posted_at
  end

  test "on a host whose review is several calls each line comment is kept as it lands, and a retry after the body failed posts only the body" do
    gitlab_review!
    on_line = create_finding
    unplaceable = create_finding(claim: "Bound the queue", position: 2, line: 300)
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == REVIEW && given[:comments].sole.line == 12 && (@posts << [ called, given ]) }
                                    .returns(Integrations::PullRequestReviews::Posted.new(reference: nil, comments: [ "d1/701" ], urls: [ "https://example.com/c701" ]))
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == REVIEW && given[:comments].sole.line == 300 && (@posts << [ called, given ]) }
                                    .returns(Integrations::PullRequestReviews::Posted.new(reference: nil, comments: [ nil ]))
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == COMMENT && (@posts << [ called, given ]) }.returns(nil)

    assert_raises(PullRequestReviewPosting::NotPosted) { posting.run!(PullRequestReview::CHANGE_FINISHED) }
    assert_equal [ "d1/701", nil ], [ on_line.reload.host_comment_id, @review.reload.review_comment_id ]

    @posts = []
    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == REVIEW && given[:comments].sole.line == 300 && (@posts << [ called, given ]) }
                                    .returns(Integrations::PullRequestReviews::Posted.new(reference: nil, comments: [ nil ]))
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == COMMENT && (@posts << [ called, given ]) }.returns([ "900", "https://example.com/r900" ])
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == EDIT && (@posts << [ called, given ]) }.returns("100")
    @review.update_columns(summary_comment_id: "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)

    assert_not(@posts.any? { |called, given| called == REVIEW && given[:comments].sole.line == 12 }, "a line comment that landed is never posted again")
    body = @posts.find { |called, _| called == COMMENT }.last[:body]
    assert_includes body, "Halon found 2 problems in aaaaaaa, 1 on its line."
    assert_includes body, unplaceable.claim
    assert_equal [ "900", "https://example.com/r900" ], [ @review.reload.review_comment_id, unplaceable.reload.host_comment_url ]
  end

  test "a post an approval rule holds parks the posting, sends nothing else while it waits, and is made and recorded once approved" do
    tool = @row.integration.tools.create!(name: "comment_on_pull_request", description: "Comments.", enabled: true, read_only: false)
    action = tool.ability_action || tool.sync_ability_action!
    Ability::Grant.grant!(workspace: @workspace, principal: SystemAgent.pull_request_review, target: { action: action })
    approval = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                         principal_label: "Halon pull request review", action_key: tool.action_key, request_digest: "d", scope: {}, params: {},
                                         required_role: WorkspaceMembership.roles[:admin])
    calls = 0
    Integrations::PullRequestReviews.stubs(:call!).with { |*| (calls += 1) == 1 }.raises(AbilityGateway::PendingApproval.new(approval))

    posting.run!(PullRequestReview::CHANGE_STARTED)
    posting.run!(PullRequestReview::CHANGE_STARTED)

    assert_equal 1, calls, "nothing else is sent while a post waits on its approval"
    assert_equal approval.id, @review.reload.held_approval_id
    payload = approval.reload.resume_payload
    assert_equal [ ApprovalResumption::KIND_PULL_REQUEST_REVIEW, "comment", "summary" ], [ payload["kind"], payload["operation"], payload.dig("purpose", "record") ]

    approval.update_columns(status: Ability::Approval::STATUS_APPROVED)
    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.expects(:call!).with { |_row, called, **given| called == COMMENT && given[:body] == payload.dig("given", "body") }.returns("100")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == EDIT }.returns("100")
    PullRequestReviewPosting.any_instance.expects(:authorizer).with(approval.id).returns(->(_tool, _arguments, &run) { run.call })
    PullRequestReviewPosting.any_instance.stubs(:authorizer).with(nil).returns(->(_tool, _arguments, &run) { run.call })

    posting.run!(PullRequestReviewPosting::RESUMED, approval_id: approval.id)

    assert_equal [ "100", nil ], [ @review.reload.summary_comment_id, @review.held_approval_id ]
  end

  test "an approval decided either way stops the hold, and an approved one queues the held post" do
    approval = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                         principal_label: "Halon pull request review", action_key: "github.comment_on_pull_request", request_digest: "d", scope: {}, params: {},
                                         status: Ability::Approval::STATUS_DENIED, required_role: WorkspaceMembership.roles[:admin])
    @review.update_columns(held_approval_id: approval.id)

    PullRequestReviewPosting.decided(approval, { "review_id" => @review.id })

    assert_nil @review.reload.held_approval_id
  end

  test "a public repository gets each finding in code terms with a link to its evidence, and the summary names nothing internal" do
    Integrations::PullRequestReviews.unstub(:public?)
    Integrations::PullRequestReviews.stubs(:public?).returns(true)
    @review.update_columns(summary_comment_id: "100", risk: PullRequestReview::RISK_HIGH, risk_reason: "Checkout depends on it, as in INC-012.", summary: "Touches payments-api.")
    finding = create_finding
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    FirefightAi::PublicFinding.any_instance.expects(:rewrite).once
                              .returns(FirefightAi::PublicFinding::Rewritten.new(why: "The retry runs with no wait.", failure_chain: [ "perform_later has no wait" ]))
    answer(REVIEW => Integrations::PullRequestReviews::Posted.new(reference: "55", comments: [ "701" ]), EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)

    line = @posts.find { |called, _| called == REVIEW }.last[:comments].sole.body
    page = Rails.application.routes.url_helpers.halon_pull_request_review_path(@review)
    assert_includes line, "The retry runs with no wait."
    assert_includes line, "1. perform_later has no wait"
    assert_includes line, "[See the evidence in Firefight]("
    assert_includes line, "#{page}#finding-#{finding.id})"
    assert_not_includes line, "INC-012"
    assert_not_includes line, "It waits five minutes"
    assert_not_includes line, "Instructions for a coding agent"
    summary = @posts.find { |called, _| called == EDIT }.last[:body]
    assert_includes summary, "**Risk: High.**"
    assert_not_includes summary, "INC-012"
    assert_not_includes summary, "payments-api"
    assert_includes summary, "See the evidence in Firefight"
  end

  test "a private repository posts the evidence as it is" do
    @review.update_columns(summary_comment_id: "100")
    create_finding
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    FirefightAi::PublicFinding.any_instance.expects(:rewrite).never
    answer(REVIEW => Integrations::PullRequestReviews::Posted.new(reference: "55", comments: [ "701" ]), EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)

    line = @posts.find { |called, _| called == REVIEW }.last[:comments].sole.body
    assert_includes line, "Seen before in [INC-012]"
    assert_not_includes line, "See the evidence in Firefight"
  end

  test "a host that renders no collapsed block or hidden text gets plain sections and no hidden id" do
    finding = create_finding(checks: [ "run_tests: test/jobs/retry_job_test.rb" ])
    plain = PullRequestReview::Comments.new(collapses: false, hides: false).finding(finding)
    folded = PullRequestReview::Comments.new.finding(finding)

    assert_not_includes plain, "<details>"
    assert_not_includes plain, "<!--"
    assert_includes plain, "**How Halon checked**"
    assert_includes folded, "<details><summary>How Halon checked</summary>"
    assert_includes folded, "<!-- halon-finding: #{finding.id} -->"
  end

  test "line comments that went up but could not be read back open at the review and are not posted again" do
    @review.update_columns(summary_comment_id: "100")
    finding = create_finding
    @review.finish!(status: PullRequestReview::STATUS_DONE)
    answer(REVIEW => Integrations::PullRequestReviews::Posted.new(reference: "55", comments: [], url: "https://example.com/r55", unread: true), EDIT => "100")

    posting.run!(PullRequestReview::CHANGE_FINISHED)

    assert_equal [ REVIEW, EDIT ], @posts.map(&:first)
    assert_equal "https://example.com/r55", finding.reload.host_comment_url
  end

  test "a failed review says it stopped and never that it found nothing" do
    @review.update_columns(error_summary: PullRequestReview::GAVE_UP, status: PullRequestReview::STATUS_FAILED)

    body = PullRequestReview::Comments.new.summary(@review.reload, [])

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

  def gitlab_review!
    gitlab = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "gitlab", name: "GitLab")
    @row = gitlab.integration_environments.create!
    @review.update_columns(integration_environment_id: @row.id)
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
