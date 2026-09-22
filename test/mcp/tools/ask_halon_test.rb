require "test_helper"

class Mcp::Tools::AskHalonTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
  end

  test "a question is answered in one call, as whoever the key belongs to" do
    answered_as = nil
    Conversation::Runner.any_instance.stubs(:run).with { true }.returns(
      FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
    )
    Conversation::Runner.stubs(:new).with { |_conversation, asker:| answered_as = asker; true }.returns(stub(run: answered_outcome, reply: "Two deploys went out."))

    response = Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "What changed today?" })

    assert_equal "Two deploys went out.", response.structured_content[:answer]
    assert_equal @member, answered_as
  end

  test "the chat is kept, so the next question from the same key carries on with it" do
    Conversation::Runner.stubs(:new).returns(stub(run: answered_outcome, reply: "ok"))

    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "one" })
    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "two" })

    conversation = @workspace.conversations.sole
    assert_equal Conversation::KIND_MCP, conversation.kind
    assert_equal @member, conversation.started_by
    assert_equal %w[one two], conversation.chat.readable_messages.map(&:content)
  end

  test "a service key or an agent gets a chat of its own, as itself" do
    key = api_keys(:full_access_key)
    Conversation::Runner.stubs(:new).returns(stub(run: answered_outcome, reply: "ok"))

    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: key, args: { question: "who owns checkout?" })

    assert_equal key, @workspace.conversations.sole.started_by
  end

  test "naming an incident puts the question in a chat about that incident, apart from the general one" do
    Conversation::Runner.stubs(:new).returns(stub(run: answered_outcome, reply: "ok"))
    incident = incidents(:active_critical_ws1)

    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "what changed?" })
    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "what is going on?", incident: incident.identifier })
    Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "and now?", incident: incident.identifier })

    assert_equal [ nil, incident ], @workspace.conversations.order(:created_at).map(&:subject)
    assert_equal [ "what is going on?", "and now?" ], @workspace.conversations.find_by(subject: incident).chat.readable_messages.map(&:content)
  end

  test "a change that needs confirming is not left hanging, the caller is told what is waiting" do
    conversation = Conversation.for_mcp!(workspace: @workspace, principal: @member)
    chat = conversation.chat_record
    chat.add_message(RubyLLM::Message.new(
      role: :assistant, content: "",
      tool_calls: { "c1" => RubyLLM::ToolCall.new(id: "c1", name: Mcp::Tools::DELETE_SEVERITY, arguments: { "slug" => "sev-4" }) }
    ))
    chat.request_decisions!([ "c1" ])
    Conversation::Runner.stubs(:new).returns(stub(run: waiting_outcome, reply: nil))

    response = Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "delete sev-4" })

    assert_equal "waiting", response.structured_content[:status]
    assert_match "Delete severity", response.structured_content[:waiting_on].first
  end

  test "an empty question is refused" do
    response = Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "  " })

    assert response.error?
  end

  test "a workspace without the agent says why" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    response = Mcp::Tools::AskHalon.perform_with_principal(workspace: @workspace, principal: @member, args: { question: "hi" })

    assert response.error?
    assert_match "not turned on", response.content.first[:text]
  end

  private

  def answered_outcome
    FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0)
  end

  def waiting_outcome
    FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_WAITING, turns_used: 1, spent_micros: 0)
  end
end
