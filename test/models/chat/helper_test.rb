require "test_helper"

class Chat::HelperTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @chat = Conversation.start_personal!(workspace: @workspace, member: @bob).chat_record
  end

  test "at most four checks are handed off in one call" do
    refused = start(5)

    assert_equal "Hand off at most #{Chat::Helper::MAX_AT_ONCE} checks in one call.", refused
    assert_empty @chat.helpers
  end

  test "one question starts at most eight helpers in all, counted from when it began" do
    start(4, since: 1.minute.ago)
    start(4, since: 1.minute.ago, tool_call_id: "call_2")

    refused = start(1, since: 1.minute.ago, tool_call_id: "call_3")

    assert_equal "Helpers already ran 8 checks for this, and at most #{Chat::Helper::MAX_PER_QUESTION} run for one question. Read the rest yourself.", refused
    assert_equal 1, start(1, since: 1.minute.from_now, tool_call_id: "call_4").size
  end

  test "a workspace runs at most twelve helpers at once, across every chat" do
    other = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one)).chat_record
    3.times { |index| Chat::Helper.start!(chat: other, tool_call_id: "other_#{index}", checks: checks(4), since: 1.minute.from_now) }

    refused = start(1)

    assert_equal "12 helpers are already running in this workspace, which is as many as run at once. Read these yourself, or hand off fewer.", refused
    other.helpers.first.finish!(Chat::Helper::STATUS_REPORTED, report: "Done.")
    assert_equal 1, start(1).size
  end

  test "a helper ends once, so a report and a stop arriving together leave one" do
    helper = start(1).sole

    assert helper.finish!(Chat::Helper::STATUS_REPORTED, report: "web logs show 3 new errors (steps 4, 6)")
    assert_not helper.finish!(Chat::Helper::STATUS_STOPPED, ended_because: Chat::Helper::STOPPED)

    assert_equal [ Chat::Helper::STATUS_REPORTED, "- Check 1: web logs show 3 new errors (steps 4, 6)" ], [ helper.status, helper.line ]
  end

  test "a helper whose asking call was closed as interrupted ends saying so, rather than running forever" do
    asked = @chat.add_message(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asked.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: Chat::Tools::Helpers::NAME, arguments: {})
    helper = start(1).sole

    @chat.close_unfinished_calls!

    assert_equal [ Chat::Helper::STATUS_FAILED, Chat::Helper::INTERRUPTED ], [ helper.reload.status, helper.ended_because ]
  end

  test "the report is kept encrypted" do
    helper = start(1).sole
    helper.finish!(Chat::Helper::STATUS_REPORTED, report: "db-1 holds 812 connections")

    stored = Chat::Helper.connection.select_value("SELECT report FROM chat_helpers WHERE id = '#{helper.id}'")
    assert_not_includes stored, "812"
  end

  private

  def checks(count) = Array.new(count) { |index| Chat::Helpers::Check.new(title: "Check #{index + 1}", brief: "Read #{index + 1}", deep: false) }

  def start(count, since: 1.minute.ago, tool_call_id: "call_1")
    Chat::Helper.start!(chat: @chat, tool_call_id: tool_call_id, checks: checks(count), since: since)
  end
end
