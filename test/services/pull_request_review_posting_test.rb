require "test_helper"

class PullRequestReviewPostingTest < ActiveSupport::TestCase
  REVIEW = Integrations::PullRequestReviews::REVIEW
  COMMENT = Integrations::PullRequestReviews::COMMENT
  EDIT = Integrations::PullRequestReviews::EDIT
  REPLY = Integrations::PullRequestReviews::REPLY

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
    PullRequestReviewPosting.any_instance.expects(:authorizer).with { |id, *| id == approval.id }.returns(->(_tool, _arguments, &run) { run.call })
    PullRequestReviewPosting.any_instance.stubs(:authorizer).with { |id, *| id.nil? }.returns(->(_tool, _arguments, &run) { run.call })

    posting.run!(PullRequestReviewPosting::RESUMED, approval_id: approval.id)

    assert_equal [ "100", nil ], [ @review.reload.summary_comment_id, @review.held_approval_id ]
  end

  test "a held body is recorded with its id and page once approved, and a held whole review the host refuses goes again the usual way" do
    approval = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                         principal_label: "Halon pull request review", action_key: "gitlab.comment_on_merge_request", request_digest: "d", scope: {}, params: {},
                                         status: Ability::Approval::STATUS_APPROVED, required_role: WorkspaceMembership.roles[:admin])
    github_row = @row
    gitlab_review!
    elsewhere = create_finding(outside_diff: true)
    @review.update_columns(summary_comment_id: "100", status: PullRequestReview::STATUS_DONE)
    @review.hold!(approval, operation: COMMENT, given: { body: "The review", with_link: true }, purpose: { "record" => "body", "finding_ids" => [ elsewhere.id ] })
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **given| called == COMMENT && given[:with_link] }.returns([ "900", "https://example.com/r900" ])
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == EDIT }.returns("100")

    posting.run!(PullRequestReviewPosting::RESUMED, approval_id: approval.id)

    assert_equal [ "900", "https://example.com/r900" ], [ @review.reload.review_comment_id, elsewhere.reload.host_comment_url ]

    whole = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                      principal_label: "Halon pull request review", action_key: "github.review_pull_request", request_digest: "e", scope: {}, params: {},
                                      status: Ability::Approval::STATUS_APPROVED, required_role: WorkspaceMembership.roles[:admin])
    @review.update_columns(review_comment_id: nil, review_posted_at: Time.current, integration_environment_id: github_row.id)
    elsewhere.update_columns(host_comment_url: nil)
    @review.hold!(whole, operation: REVIEW, given: { body: "All", comments: [] }, purpose: { "record" => "whole", "on_lines" => [], "elsewhere" => [ elsewhere.id ] })
    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REVIEW }.raises(Integrations::PullRequestReviews::Refused, "No")

    assert_raises(PullRequestReviewPosting::NotPosted) { PullRequestReviewPosting.new(@review.reload).run!(PullRequestReviewPosting::RESUMED, approval_id: whole.id) }
    assert_nil @review.reload.review_posted_at, "the claim is handed back so the job's retry posts the review"
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
    assert_equal [ "701", "200", "100" ], edits.map { |given| given[:reference] }
    assert_equal [ true, false, false ], edits.map { |given| given[:line] || false }
    assert edits.first(2).all? { |given| given[:body].start_with?("Fixed in bbbbbbb.") }
    assert_includes edits.last[:body], "0 open, 1 fixed."
  end

  test "a finding from a strict lesson that is overridden edits its line comment and its own comment while still open" do
    @review.update_columns(summary_comment_id: "100")
    lesson = Chat::Memory.create!(workspace: @workspace, text: "Retries need a backoff", source: incidents(:active_critical_ws1), state: Chat::Memory::STATE_UNCONFIRMED)
    lesson.approve!(by: workspace_memberships(:alice_workspace_one), strict: true)
    finding = create_finding(serious: true, lesson: lesson)
    finding.update_columns(host_comment_id: "701", serious_comment_id: "200")
    finding.override!(by: workspace_memberships(:alice_workspace_one), reason: "Behind a flag")
    answer(EDIT => "x")

    posting.run!(PullRequestReview::CHANGE_FINDING_CHANGED, finding: finding.reload)

    edits = @posts.map(&:last)
    assert_equal [ "701", "200", "100" ], edits.map { |given| given[:reference] }
    assert edits.first(2).all? { |given| given[:body].include?("Lesson from INC-001") && !given[:body].include?("check fails") }
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

  test "a reply the host refuses for good goes up as a comment on the pull request that names its finding, once" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701", host_comment_url: "https://example.com/pull/7#discussion_r701")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY }.raises(answered(404, "GitHub has no review comment 701 on pull request 7 in acme/api."))
    readable_conversation!
    answer(COMMENT => "300")

    posting.reply!(finding, "Fixed in bbbbbbb. The job now waits.", then_resolve: true)

    assert_equal [ COMMENT ], @posts.map(&:first), "a thread that refused the reply is not resolved and nothing is tried twice"
    body = @posts.sole.last[:body]
    assert_includes body, "[Queue the retry for its backoff delay](https://example.com/pull/7#discussion_r701)"
    assert_includes body, "`app/jobs/retry_job.rb` line 12"
    assert_includes body, "Fixed in bbbbbbb. The job now waits."
    assert_no_dashes_or_semicolons(body)
    said = finding.reload.thread_said.sole
    assert_equal [ nil, true, "Fixed in bbbbbbb. The job now waits." ], said.values_at("comment", "halon", "body")
    assert_empty finding.unposted_replies
  end

  test "a thread that refused a reply for good is never tried again, and later replies stay on the review page, never another comment" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    replies = 0
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY && (replies += 1) }.raises(answered(404, "GitHub has no review comment 701."))
    readable_conversation!
    answer(COMMENT => "300")

    posting.reply!(finding, "Not fixed yet in bbbbbbb.", recheck: true)
    posting.reply!(finding.reload, "Fixed in ccccccc.", then_resolve: true, recheck: true)
    posting.reply!(finding.reload, "Still fixed.")

    assert_equal 1, replies, "a thread refused for good is not asked again"
    assert_equal [ COMMENT ], @posts.map(&:first), "only the first refused reply goes in the conversation"
    assert_equal "GitHub has no review comment 701.", finding.reload.thread_refusal
    kept = finding.unposted_replies
    assert_equal [ "Fixed in ccccccc.", "Still fixed." ], kept.map { |reply| reply["body"] }
    assert kept.all? { |reply| reply["reason"].include?("GitHub has no review comment 701.") }
  end

  test "a reply refused as not found while the pull request cannot be read either is the connection's access, kept on the review page and never in the conversation" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY }.raises(answered(404, "GitHub has no review comment 701."))
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == Integrations::PullRequestReviews::CONVERSATION }
                                     .raises(answered(404, "GitHub has no pull request 7 in acme/api."))
    Integrations::PullRequestReviews.expects(:call!).with { |_row, called, **| called == COMMENT }.never

    assert_nil posting.reply!(finding, "Fixed.")

    assert_nil finding.reload.thread_refusal
    kept = finding.unposted_replies.sole
    assert_equal "Fixed.", kept["body"]
    assert_equal "GitHub has no review comment 701. #{PullRequestReviewPosting::ACCESS_HINT}", kept["reason"]
  end

  test "a reply refused for Firefight's own credential or permission is kept on the review page with why, never in the conversation, and the thread is asked again next time" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    refusals = [
      Integrations::GithubApp::NotPermitted.new("GitHub refused this: Resource not accessible by integration.").tap { |error| error.http_status = 403 },
      Integrations::GitlabApi::Refused.new("GitLab answered 403: You cannot reply to a locked discussion.").tap { |error| error.http_status = 403 },
      answered(401, "Bitbucket answered 401: Token expired.")
    ]
    replies = 0
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY && (replies += 1) }.raises(refusals[0]).then.raises(refusals[1]).then.raises(refusals[2])
    Integrations::PullRequestReviews.expects(:call!).with { |_row, called, **| called == COMMENT }.never

    3.times { |index| assert_nil posting.reply!(finding.reload, "Reply #{index}.") }

    assert_equal 3, replies, "an access refusal says nothing about the thread, so it is asked again"
    assert_nil finding.reload.thread_refusal
    assert_equal [ "Reply 0.", "Reply 1.", "Reply 2." ], finding.unposted_replies.map { |reply| reply["body"] }
    assert_equal "GitLab answered 403: You cannot reply to a locked discussion. #{PullRequestReviewPosting::ACCESS_HINT}", finding.unposted_replies.second["reason"]
    assert_no_match(/[—;]/, PullRequestReviewPosting::ACCESS_HINT)
  end

  test "the review page keeps the newest replies that could not be posted, at most twenty" do
    finding = create_finding

    25.times { |index| finding.unposted_reply!(body: "Reply #{index}.", reason: "Locked.") }

    kept = finding.reload.unposted_replies
    assert_equal PullRequestReview::Finding::Threading::UNPOSTED_KEPT, kept.size
    assert_equal [ "Reply 5.", "Reply 24." ], [ kept.first["body"], kept.last["body"] ]
  end

  test "a reply refused for good whose comment is refused too stays on the review page with why" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY }.raises(answered(422, "GitHub answered 422: The conversation is locked."))
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == COMMENT }.raises(answered(403, "GitHub answered 403: Resource not accessible."))

    posting.reply!(finding, "Not fixed yet in bbbbbbb.")

    kept = finding.reload.unposted_replies.sole
    assert_equal "Not fixed yet in bbbbbbb.", kept["body"]
    assert_includes kept["reason"], "The conversation is locked."
    assert_includes kept["reason"], "Resource not accessible."
    assert kept["at"].present?
    assert_empty finding.thread_said
  end

  test "a finding with no page of its own is named by its claim in the comment" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY }.raises(answered(404, "Gone."))
    readable_conversation!
    answer(COMMENT => "300")

    posting.reply!(finding, "Still open.")

    assert_includes @posts.sole.last[:body], "**Queue the retry for its backoff delay**"
  end

  test "a reply the host turned down for now, or one Firefight's own settings stopped, is not posted anywhere else" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    Integrations::PullRequestReviews.expects(:call!).with { |_row, called, **| called == COMMENT }.never
    [ Integrations::Error.new("GitHub answered 429: slow down").extend(Integrations::RateLimited),
      Integrations::Error.new("GitHub answered 502: bad gateway").tap { |error| error.http_status = 502 },
      Integrations::Error.new("timed out").extend(Integrations::TimedOut),
      Integrations::PullRequestReviews::ToolOff.new("GitHub's reply_to_review_comment is switched off under Integrations."),
      AbilityGateway::Denied.new("github.reply_to_review_comment") ].each do |error|
      Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY }.raises(error)

      assert_nil posting.reply!(finding, "Fixed.")
    end
    assert_empty finding.reload.unposted_replies
  end

  test "a held reply the host refuses for good once approved goes up as a comment" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    approval = Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                                         principal_label: "Halon pull request review", action_key: "github.reply_to_review_comment", request_digest: "d", scope: {}, params: {},
                                         status: Ability::Approval::STATUS_APPROVED, required_role: WorkspaceMembership.roles[:admin])
    @review.update_columns(summary_comment_id: "100")
    @review.hold!(approval, operation: REPLY, given: { reference: "701", body: "Fixed." }, purpose: { "record" => "reply", "finding_id" => finding.id, "body" => "Fixed.", "resolve" => true })
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == REPLY }.raises(answered(404, "GitHub has no review comment 701."))
    readable_conversation!
    answer(COMMENT => "300", EDIT => "100")

    posting.run!(PullRequestReviewPosting::RESUMED, approval_id: approval.id)

    elsewhere = @posts.find { |called, _given| called == COMMENT }
    assert_includes elsewhere.last[:body], "Fixed."
    assert_includes elsewhere.last[:body], "Queue the retry for its backoff delay"
    assert_nil @review.reload.held_approval_id
  end

  test "a held comment for a refused reply is posted once approved and kept as said, and one refused once approved stays on the review page" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701", thread_refusal: "GitHub has no review comment 701.", thread_refused_at: Time.current)
    @review.update_columns(summary_comment_id: "100")
    purpose = { "record" => "reply_elsewhere", "finding_id" => finding.id, "body" => "Fixed.", "refused" => "GitHub has no review comment 701." }
    approved = approved_approval("github.comment_on_pull_request")
    @review.hold!(approved, operation: COMMENT, given: { body: "About my finding, Fixed." }, purpose: purpose)
    answer(COMMENT => "300", EDIT => "100")

    posting.run!(PullRequestReviewPosting::RESUMED, approval_id: approved.id)

    assert_equal [ nil, true, "Fixed." ], finding.reload.thread_said.sole.values_at("comment", "halon", "body")
    assert_empty finding.unposted_replies

    again = approved_approval("github.comment_on_pull_request")
    @review.reload.hold!(again, operation: COMMENT, given: { body: "About my finding, Still fixed." }, purpose: purpose.merge("body" => "Still fixed."))
    Integrations::PullRequestReviews.unstub(:call!)
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == COMMENT }.raises(answered(403, "GitHub answered 403: Resource not accessible."))
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == EDIT }.returns("100")

    PullRequestReviewPosting.new(@review.reload).run!(PullRequestReviewPosting::RESUMED, approval_id: again.id)

    kept = finding.reload.unposted_replies.sole
    assert_equal "Still fixed.", kept["body"]
    assert_includes kept["reason"], "GitHub has no review comment 701."
    assert_includes kept["reason"], "Resource not accessible."
  end

  test "a claim, a path and a link are written as text in the comment, so nothing in them breaks its markdown" do
    finding = create_finding(claim: "Wrap `retry` in **[brackets]** (see #12)\nnow", path: "app/jobs/`odd`_job.rb")
    finding.update_columns(host_comment_url: "https://example.com/pull/7 (x)")

    lead = PullRequestReview::Comments.elsewhere_reply(finding.reload, "Body.").lines.first.chomp

    assert_equal "About my finding on ``app/jobs/`odd`_job.rb`` line 12, " \
                 "[Wrap \\`retry\\` in \\*\\*\\[brackets\\]\\*\\* \\(see \\#12\\) now](https://example.com/pull/7%20%28x%29)", lead
  end

  test "a comment for a refused reply that waited behind a held post goes up as a comment once caught up" do
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    @review.update_columns(pending_posts: [ { "kind" => PullRequestReview::PENDING_REPLY, "finding_id" => finding.id, "body" => "Fixed.", "resolve" => false,
                                              "recheck" => true, "refused" => "GitHub has no review comment 701." } ])
    answer(COMMENT => "300")

    posting.run!(PullRequestReviewPosting::CAUGHT_UP)

    assert_equal [ COMMENT ], @posts.map(&:first)
    assert_includes @posts.sole.last[:body], "Fixed."
    assert_empty @review.reload.pending_posts
  end

  test "a reply the host refuses is in the activity log with the host's own words" do
    tool = @row.integration.tools.create!(name: "reply_to_review_comment", description: "Replies.", enabled: true, read_only: false)
    Ability::Grant.grant!(workspace: @workspace, principal: SystemAgent.pull_request_review, target: { action: tool.ability_action || tool.sync_ability_action! })
    finding = create_finding
    finding.update_columns(host_comment_id: "701")
    Integrations::NativeExecutor.stubs(:call).raises(answered(404, "GitHub has no review comment 701 on pull request 7 in acme/api."))

    posting.reply!(finding, "Fixed.")

    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: tool.action_key)
    assert_equal [ Ability::Invocation::OUTCOME_ERROR, "GitHub has no review comment 701 on pull request 7 in acme/api." ], [ invocation.outcome, invocation.error_summary ]
  end

  private

  def posting = PullRequestReviewPosting.new(@review.reload)

  def approved_approval(action_key)
    Ability::Approval.create!(workspace: @workspace, principal_type: SystemAgent.polymorphic_name, principal_id: SystemAgent.pull_request_review.id,
                              principal_label: "Halon pull request review", action_key: action_key, request_digest: SecureRandom.hex(4), scope: {}, params: {},
                              status: Ability::Approval::STATUS_APPROVED, required_role: WorkspaceMembership.roles[:admin])
  end

  # The pull request is still there to read, so a comment not found is the thread's and not the connection's access.
  def readable_conversation!
    Integrations::PullRequestReviews.stubs(:call!).with { |_row, called, **| called == Integrations::PullRequestReviews::CONVERSATION }.returns([])
  end

  def answered(status, message) = Integrations::Error.new(message).tap { |error| error.http_status = status }

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
