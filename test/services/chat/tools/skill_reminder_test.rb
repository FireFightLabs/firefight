require "test_helper"

class Chat::Tools::SkillReminderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @conversation.chat_record
    @declaring = Chat::Skill.available_to(@workspace).find { |skill| skill.tools.include?(Mcp::Tools::DECLARE_INCIDENT.to_s) }
  end

  test "the first call to a tool a skill covers names the skill, when the chat has not loaded it" do
    called("call_1", Mcp::Tools::DECLARE_INCIDENT)

    reminder = remind("call_1")

    assert_includes reminder, "load it with use_skill before going further"
    assert_includes reminder, "#{@declaring.name}: #{@declaring.used_when}"
  end

  test "a skill the chat has loaded is never named again" do
    called("call_1", Chat::Tools::UseSkill.tool_name, "skill" => @declaring.name)
    called("call_2", Mcp::Tools::DECLARE_INCIDENT)

    assert_nil remind("call_2")
  end

  test "a skill is named once, on the first call, and a later call is not told again" do
    called("call_1", Mcp::Tools::DECLARE_INCIDENT)
    called("call_2", Mcp::Tools::DECLARE_INCIDENT)

    assert remind("call_1")
    assert_nil remind("call_2")
  end

  test "a skill open_tools already listed is not named again" do
    called("call_1", Chat::Tools::Open.tool_name, "group" => Chat::Tools::Groups::INCIDENT_RESPONSE)
    @chat.add_message(role: :tool, content: "Skills with the steps for these tools.\n#{@declaring.name}: #{@declaring.used_when}", tool_call_id: "call_1")
    called("call_2", Mcp::Tools::DECLARE_INCIDENT)

    assert_nil remind("call_2")
  end

  test "a run is never pointed at a skill, since skills are chat work" do
    called("call_1", Mcp::Tools::DECLARE_INCIDENT)
    run = Investigation.new(workspace: @workspace)

    assert_nil Chat::Tools::SkillReminder.for(run, source: Chat::Skill::SOURCE_FIREFIGHT, handle: Mcp::Tools::DECLARE_INCIDENT.to_s, tool_call_id: "call_1")
  end

  private

  def called(id, name, arguments = {})
    call = RubyLLM::ToolCall.new(id: id, name: name.to_s, arguments: arguments)
    @chat.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { id => call }))
  end

  def remind(tool_call_id)
    turn = Conversation::Turn.new(@conversation, asker: workspace_memberships(:alice_workspace_one))
    Chat::Tools::SkillReminder.for(turn, source: Chat::Skill::SOURCE_FIREFIGHT, handle: Mcp::Tools::DECLARE_INCIDENT.to_s, tool_call_id: tool_call_id)
  end
end
