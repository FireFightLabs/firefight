require "test_helper"

# A chat started in a tracker's issue is never opened in Firefight, so a call an approval rule held there runs once an
# approver approves it on Gateway, Approvals, with nothing else pressed, and Halon says in the issue how it went.
class IssueChatApprovalsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class FakeResponder
    def initialize(conversation, reply)
      @conversation = conversation
      @reply = reply
    end

    def run(**)
      @conversation.reload.chat.add_message(role: :assistant, content: @reply)
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
    end

    def ai_model = FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", settings: {})
    integration.integration_environments.create!.store_installation!("org-1")
    @conversation = Conversation.start_in_issue!(integration: integration, session_id: "session-1", title: "ENG-12 Checkout", issue_key: "ENG-12")
    @conversation.ask!("Scale web down.", asker: @conversation.started_by)
    @said = []
    Integrations::AgentSessions::Linear.any_instance.stubs(:say).with { |_session_id, activity| @said << activity }
    AppUrl.stubs(:options).returns(host: "ff.example.com", protocol: "https")
    Chat::Tools::LookFirst.stubs(:refusal).returns(nil)
    ConversationChannel.stubs(:broadcast_to)
    Conversation::Tools.stubs(:for).returns([])

    faylee = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Faylee", slug: "faylee",
                                             settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    faylee.integration_environments.create!
    tool = faylee.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: SystemAgent.investigator, action: tool.ability_action)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    turn = Conversation::Turn.new(@conversation, asker: @conversation.started_by)
    Chat::Tools::Connection.new(turn, tool).call(tool_call: stub(id: "call_2"), "code" => "scale web to 0")
    @held = @conversation.chat.held_calls.sole
  end

  test "approving the call on the Approvals page runs it, as the agent, and Halon says in the issue how it went" do
    sign_in(users(:alice), @workspace)

    post approve_approval_url(@held.approval)

    assert_equal "You approved #{SystemAgent.investigator.actor_display_name}'s request. It runs now.", flash[:notice]
    Integrations::McpExecutor.expects(:call).once.returns("content" => [ { "type" => "text", "text" => "web scaled to 0" } ])
    FirefightAi::Responder.stubs(:new).returns(FakeResponder.new(@conversation, "Web is scaled down to zero."))

    perform_enqueued_jobs(only: AbilityApprovalResumptionJob)
    assert_equal Chat::HeldCall::STATUS_RUNNING, @held.reload.status
    assert_enqueued_with(job: ConversationReplyJob, args: [ @conversation.id, workspace_memberships(:alice_workspace_one).id, @held.id ])
    perform_enqueued_jobs(only: ConversationReplyJob)

    @held.reload
    assert_equal [ Chat::HeldCall::STATUS_RAN, workspace_memberships(:alice_workspace_one) ], [ @held.status, @held.decided_by ]
    ran = Ability::Invocation.find_by!(approval_id: @held.approval_id, decision: Ability::Invocation::DECISION_ALLOW)
    assert_equal [ SystemAgent.name, SystemAgent.investigator.id ], [ ran.principal_type, ran.principal_id ]
    assert_equal [ Integrations::AgentSessions::RESPONSE, "Web is scaled down to zero." ], [ @said.last.kind, @said.last.body ]
  end

  test "a call held in any other chat still waits for someone to press Run once approved" do
    personal = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @held.chat.update_columns(owner_id: personal.id)
    Chat::StateCheck.stubs(:run).returns(Chat::CurrentState::Report.new(state: nil, change: nil, checked_at: nil))
    sign_in(users(:alice), @workspace)

    post approve_approval_url(@held.approval)

    assert_match "They can run it now.", flash[:notice]
    assert_no_enqueued_jobs(only: ConversationReplyJob) { perform_enqueued_jobs(only: AbilityApprovalResumptionJob) }
    assert_equal Chat::HeldCall::STATUS_CHECKING, @held.reload.status
  end

  test "a denied call never runs" do
    sign_in(users(:alice), @workspace)
    Integrations::McpExecutor.expects(:call).never

    post deny_approval_url(@held.approval)
    perform_enqueued_jobs(only: AbilityApprovalResumptionJob)
    assert_no_enqueued_jobs(only: ConversationReplyJob)

    assert_equal Chat::HeldCall::STATUS_DENIED, @held.reload.status
  end
end
