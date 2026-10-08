require "test_helper"

# Halon owns the pull requests it opens: it follows each through the code host, says once when one conflicts, fails its
# checks or is asked for changes, offers Fix it, and changes nothing on the branch until the person who asked presses it.
class PullRequestFollowingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
    @row = @github.integration_environments.create!(base_config: { "installation_id" => "12345" })
    @tool = @github.tools.create!(name: "fix_code", description: "Write a code change", params_schema: {}, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: @bob, action: @tool.ability_action)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @conversation.chat_record
    @session = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "claude-sonnet-4-5", repository: "acme/api",
                                        budget_micros: 1, expires_at: 1.hour.from_now, token_digest: SecureRandom.hex, principal: @bob, place: @conversation)
    @session.owns_pull_request!(environment_row: @row, number: 689, url: "https://github.com/acme/api/pull/689", base: "main", branch: "halon/fix-6059c4e5")
    @adapter = stub(post_pull_request_notice_to_user: { channel_id: "D1", message_id: "7.1" }, update_pull_request_notice: { success: true })
    WorkspaceAdapter.stubs(:for).returns(@adapter)
    ConversationChannel.stubs(:broadcast_to)
  end

  test "a pull request Halon opened from a chat is followed, and one nobody can be told about is not" do
    assert @session.following?
    assert_enqueued_with(job: PullRequestCheckJob, args: [ @session.id ])

    nobody = CodeAgentSession.create!(workspace: @workspace, provider: "anthropic", model: "m", repository: "acme/api", budget_micros: 1,
                                      expires_at: 1.hour.from_now, token_digest: SecureRandom.hex)
    nobody.owns_pull_request!(environment_row: @row, number: 3, url: "u", base: "main", branch: "b")
    assert_not nobody.following?
    assert CodeAgentSession.opened_pull_request?(@workspace, "acme/api", 3), "it still owns it"
  end

  test "a pull request that conflicts after a later merge to its base is told once, with Fix it, and nothing changes on its branch" do
    Integrations::NativeExecutor.expects(:call).never
    @adapter.expects(:post_pull_request_notice_to_user).once.with do |user_id:, notice:, conversation_id:|
      user_id == @bob.platform_user_id && conversation_id == @conversation.id &&
        notice.reason == "PR #689 in acme/api needs attention: it conflicts with main now."
    end.returns(channel_id: "D1", message_id: "7.1")
    reads(status(mergeable: Integrations::PullRequests::CONFLICTED))

    PullRequestFollowing.check!(@session)
    PullRequestFollowing.check!(@session, now: 2.minutes.from_now)
    PullRequestFollowing.nudged!(@row, [ Integrations::PullRequests::Nudge.new(repository: "acme/api", branches: [ "main" ]) ])
    perform_enqueued_jobs(only: PullRequestCheckJob)

    notice = @session.notices.sole
    assert_equal CodeAgentSession::Notice::STATUS_OFFERED, notice.status
    assert_equal @conversation, notice.conversation
    assert_match "Fix it has Halon merge main in and resolve the conflict on the pull request's branch", notice.offer
    assert_no_enqueued_jobs(only: ConversationReplyJob)
    note = PullRequestFollowing.untold_note(@conversation)
    assert_match "it conflicts with main now", note
    assert_match "Never change the branch unless they press Fix it", note
    assert_nil PullRequestFollowing.untold_note(@conversation), "Halon hears it once"
  end

  test "Fix it runs the code change on the pull request's branch as whoever asked, and only once they press it" do
    reads(status(mergeable: Integrations::PullRequests::CONFLICTED))
    PullRequestFollowing.check!(@session)
    notice = @session.notices.sole

    assert_equal "Only Bob Jones can press Fix it, since the change runs as them.", PullRequestFollowing.fix!(notice, by: @alice)
    assert notice.reload.offered?

    Integrations::NativeExecutor.expects(:call).once.with do |tool:, arguments:, **|
      tool == @tool && arguments["repo"] == "acme/api" && arguments["pull_request"] == 689 && arguments["brief"].include?("It conflicts with main")
    end.returns({ "content" => [ { "type" => "text", "text" => "Pushed abc to halon/fix-6059c4e5. The code host says PR #689 can merge into main." } ] })
    FirefightAi::Responder.any_instance.stubs(:run).returns(FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0))

    assert_nil PullRequestFollowing.fix!(notice, by: @bob)
    assert_equal "This was already taken care of.", PullRequestFollowing.fix!(notice.reload, by: @bob)
    assert_equal [ CodeAgentSession::Notice::STATUS_FIXING, @bob ], [ notice.status, notice.fix_by ]
    perform_enqueued_jobs(only: ConversationReplyJob)

    told = @conversation.chat.messages.where(nudge: true).order(:created_at).map(&:content).join("\n")
    assert_match "The person pressed Fix it on PR #689 in acme/api", told
    assert_match "The code host says PR #689 can merge into main.", told
    assert_match "never that a conflict is resolved unless the host says it can merge", told
  end

  test "an approval rule holds Fix it's change for its approver, so it does not run on the press alone" do
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    Integrations::NativeExecutor.expects(:call).never
    FirefightAi::Responder.any_instance.stubs(:run).returns(FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0))
    reads(status(mergeable: Integrations::PullRequests::CONFLICTED))
    PullRequestFollowing.check!(@session)

    PullRequestFollowing.fix!(@session.notices.sole, by: @bob)
    perform_enqueued_jobs(only: ConversationReplyJob)

    held = @conversation.chat.held_calls.sole
    assert_equal Chat::HeldCall::STATUS_WAITING, held.status
    assert_equal 689, held.approval.params["pull_request"]
  end

  test "failing checks and a reviewer asking for changes are told, and newer news replaces the offer nobody took" do
    reads(status(failing: [ Integrations::PullRequests::Check.new(name: "test", url: "https://ci/1") ]))
    PullRequestFollowing.check!(@session)
    first = @session.notices.sole
    assert_equal "PR #689 in acme/api needs attention: a check failed (test).", first.reason

    reads(status(failing: [ Integrations::PullRequests::Check.new(name: "test", url: "https://ci/1") ],
                 reviews: [ Integrations::PullRequests::Review.new(id: "11", reviewer: "ana", body: "Keep the old default.") ]))
    PullRequestFollowing.check!(@session, now: 15.minutes.from_now)

    assert_equal CodeAgentSession::Notice::STATUS_REPLACED, first.reload.status
    latest = @session.notices.offered.sole
    assert_equal "PR #689 in acme/api needs attention: a check failed (test) and a reviewer asked for changes (ana: Keep the old default.).", latest.reason
    assert_match "make the changes the reviewer asked for", latest.offer
  end

  test "a merged or closed pull request is no longer followed, and an offer nobody took says so" do
    reads(status(mergeable: Integrations::PullRequests::CONFLICTED))
    PullRequestFollowing.check!(@session)
    reads(status(state: Integrations::PullRequests::MERGED))

    PullRequestFollowing.check!(@session, now: 15.minutes.from_now)

    assert_equal [ Integrations::PullRequests::MERGED, CodeAgentSession::Notice::STATUS_ENDED ], [ @session.reload.pull_request_state, @session.notices.sole.status ]
    Integrations::PullRequests.expects(:status).never
    PullRequestFollowing.check!(@session, now: 30.minutes.from_now)
    assert_not_includes CodeAgentSession.follow_due(2.hours.from_now), @session
  end

  test "problems gone before anyone pressed Fix it clear the offer" do
    reads(status(mergeable: Integrations::PullRequests::CONFLICTED))
    PullRequestFollowing.check!(@session)
    reads(status)

    PullRequestFollowing.check!(@session, now: 15.minutes.from_now)

    assert_equal CodeAgentSession::Notice::STATUS_CLEARED, @session.notices.sole.status
    assert_equal "This was already taken care of.", @session.notices.sole.fix_blocked_reason(@bob)
  end

  test "the sweep reads each followed pull request once its interval passed, more slowly once it has sat a day" do
    @session.update_columns(pull_request_checked_at: 5.minutes.ago)
    assert_not_includes CodeAgentSession.follow_due, @session
    @session.update_columns(pull_request_checked_at: 11.minutes.ago)
    assert_includes CodeAgentSession.follow_due, @session
    @session.update_columns(created_at: 2.days.ago)
    assert_not_includes CodeAgentSession.follow_due, @session
    @session.update_columns(pull_request_checked_at: 2.hours.ago)
    assert_includes CodeAgentSession.follow_due, @session
  end

  private

  def reads(found)
    Integrations::PullRequests.stubs(:status).returns(found)
  end

  def status(state: Integrations::PullRequests::OPEN, mergeable: Integrations::PullRequests::MERGEABLE, failing: [], reviews: [])
    Integrations::PullRequests::Status.new(number: 689, url: "https://github.com/acme/api/pull/689", state: state, mergeable: mergeable,
                                           head_sha: "h" * 40, base: "main", failing_checks: failing, reviews: reviews)
  end
end
