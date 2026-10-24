require "test_helper"

# Alice has Halon pause a Convex deployment or a QStash schedule during an incident. Both are changes customers feel for
# a while, so the confirmation says Firefight puts them back itself, and once they run the undo is the fixed call that
# does, never a question to Halon in the chat.
class Conversation::PausedMitigationsTest < ActiveSupport::TestCase
  setup do
    Chat::Tools::LookFirst.stubs(:refusal).returns(nil)
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat = @conversation.chat_record
    executor = Object.new
    executor.define_singleton_method(:call) { |tool:, **| { "content" => [ { "type" => "text", "text" => "#{tool.name} done." } ] } }
    Integration.any_instance.stubs(:executor).returns(executor)
    Slack::WorkspaceAdapter.any_instance.stubs(:post_mitigation_notice_to_user).returns({ channel_id: "D1", message_id: "1.1" })
  end

  test "pausing a Convex deployment says it starts again automatically, and unpausing it is the undo Firefight runs" do
    convex = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "convex", name: "Convex", slug: "convex")
    convex.integration_environments.create!
    pause = convex.tools.create!(name: "pause_deployment", description: "Pause", enabled: true, read_only: false, params_schema: { "type" => "object", "properties" => {} })
    unpause = convex.tools.create!(name: "unpause_deployment", description: "Unpause", enabled: true, read_only: false, params_schema: { "type" => "object", "properties" => {} })

    mitigation = run_confirmed!(pause, {})

    assert_equal [ unpause.action_key, {}, true ], mitigation.undo_steps.sole.values_at("action_key", "arguments", "declared")
    assert mitigation.undone_by_firefight?
  end

  test "pausing a QStash schedule says it resumes automatically, and resuming the same schedule is the undo Firefight runs" do
    upstash = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash", slug: "upstash",
                                              settings: { "server_url" => "https://mcp.upstash.com/mcp" })
    upstash.integration_environments.create!
    schedule = upstash.tools.create!(name: "qstash_manage_schedule", description: "Schedules", enabled: true, read_only: false,
                                     params_schema: { "type" => "object", "properties" => { "action" => { "enum" => %w[create get delete pause resume] },
                                                                                           "scheduleId" => { "type" => "string" } } })

    mitigation = run_confirmed!(schedule, { "action" => "pause", "scheduleId" => "scd_1" }, label: Integrations::Mitigations::RESUMES)

    assert_equal [ schedule.action_key, { "action" => "resume", "scheduleId" => "scd_1" }, true ],
                 mitigation.undo_steps.sole.values_at("action_key", "arguments", "declared")
    assert mitigation.undone_by_firefight?
  end

  test "a QStash tool that offers no resume leaves the schedule for Halon to put back, and says so" do
    upstash = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash", slug: "upstash",
                                              settings: { "server_url" => "https://mcp.upstash.com/mcp" })
    upstash.integration_environments.create!
    schedule = upstash.tools.create!(name: "qstash_manage_schedule", description: "Schedules", enabled: true, read_only: false,
                                     params_schema: { "type" => "object", "properties" => { "action" => { "enum" => %w[create pause] } } })

    mitigation = run_confirmed!(schedule, { "action" => "pause" }, label: Chat::Tools::ASK_HALON_TO_PUT_BACK)

    assert_equal [ Chat::Mitigation::UNDO_IN_CHAT, [] ], [ mitigation.undo_state, mitigation.undo_steps ]
  end

  private

  def run_confirmed!(tool, arguments, label: Integrations::Mitigations::STARTS_AGAIN)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    message.ruby_llm_tool_calls.create!(tool_call_id: "call_1", name: tool.model_facing_name, arguments: arguments.merge("intent" => "Pause it"))
    @chat.request_decisions!([ "call_1" ])
    call = @chat.tool_calls.find_by!(tool_call_id: "call_1")
    Chat::Safeguards.prepare!(@turn, [ call ])

    assert_equal label, Chat::Tools.confirmation(call).undo_label

    call.update_columns(approval: Chat::APPROVAL_APPROVED)
    connection = Chat::Tools::Connection.new(@turn, tool)
    connection.call(tool_call: RubyLLM::ToolCall.new(id: "call_1", name: connection.name, arguments: arguments), **arguments.symbolize_keys)
    Chat::Mitigation.for_call(@chat, "call_1")
  end
end
