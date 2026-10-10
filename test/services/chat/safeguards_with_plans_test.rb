require "test_helper"

# The safeguards hold inside a plan: a scheduled plan's approved write is still counted, copied and checked, its stop
# still asks the owner, and a temporary change one of its steps made is put back once, by Firefight or by the plan.
class Chat::SafeguardsWithPlansTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  ARGUMENTS = { "id" => 7 }.freeze
  ApprovedPlan = Struct.new(:approved_tools)

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @chat = @conversation.chat_record
    posthog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "posthog", name: "PostHog", slug: "posthog",
                                              settings: { "server_url" => "https://mcp.posthog.com/mcp?mode=tools" })
    posthog.integration_environments.create!
    @disable = posthog.tools.create!(name: "feature_flag_disable", description: "Disable", enabled: true, read_only: false, params_schema: {})
    executor = Object.new
    executor.define_singleton_method(:call) { |**| { "content" => [ { "type" => "text", "text" => "Flag 7 is now off." } ] } }
    Integration.any_instance.stubs(:executor).returns(executor)
  end

  test "a write a scheduled plan approved ahead runs without asking, and is still counted first" do
    planetscale = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale", slug: "planetscale",
                                                  settings: { "server_url" => "https://mcp.pscale.dev/mcp/planetscale" })
    planetscale.integration_environments.create!
    write = planetscale.tools.create!(name: "execute_write_query", description: "Write", enabled: true, read_only: false, params_schema: {})
    planetscale.tools.create!(name: "execute_read_query", description: "Read", enabled: true, read_only: true, params_schema: {})
    counting = Object.new
    counting.define_singleton_method(:call) { |**| { "content" => [ { "type" => "text", "text" => '[{"halon_rows": 2}]' } ] } }
    Integration.any_instance.stubs(:executor).returns(counting)
    turn = Conversation::Turn.new(@conversation, asker: @alice, approved_plan: ApprovedPlan.new([ write.model_facing_name ]))
    tool = Chat::Tools::Connection.new(turn, write)
    call = RubyLLM::ToolCall.new(id: "call_1", name: tool.name, arguments: { "query" => "DELETE FROM carts WHERE abandoned", "check" => "SELECT id FROM carts WHERE abandoned",
                                                                            "intent" => "Clear abandoned carts" })

    assert_equal true, tool.approval_resolver.call(call)
    assert_equal 2, Chat::DataRepair.for_call(@chat, "call_1").rows_counted

    unapproved = Chat::Tools::Connection.new(Conversation::Turn.new(@conversation, asker: @alice), write)
    assert_nil unapproved.approval_resolver.call(RubyLLM::ToolCall.new(id: "call_2", name: tool.name, arguments: call.arguments)),
               "outside the plan it is asked about as before"
  end

  test "a change a plan step made that Firefight undid when its time ran out is left out of the plan's undo" do
    plan, step = plan_with_change!
    mitigation = run_as_step!(step)
    assert_equal step.id, mitigation.plan_step_id

    mitigation.update_columns(status: Chat::Mitigation::STATUS_UNDONE)
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)

    assert_not plan.reload.undo_steps.any? { |row| row["description"].start_with?("Put back step 1") }
  end

  test "pressing Undo on the plan hands a change still in place to the plan's undo, so Firefight never undoes it too" do
    plan, step = plan_with_change!
    mitigation = run_as_step!(step)
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_DONE)
    plan.update_columns(status: Chat::Plan::STATUS_STOPPED)

    Conversation::Plans.undo!(plan.reload, by: @alice)

    assert_equal Chat::Mitigation::STATUS_WITH_PLAN, mitigation.reload.status
    assert_empty Chat::Mitigation.expiry_due(2.hours.from_now).where(id: mitigation.id)
  end

  test "a step of a plan's undo that puts something back is never counted down itself" do
    plan, = plan_with_change!
    plan.update_columns(undoes_id: Chat::Plan.make!(chat: @chat, made_by: @alice, goal: "Earlier plan", steps: steps).id)

    mitigation = run_as_step!(plan.steps.first)

    assert_equal Chat::Mitigation::STATUS_CANCELLED, mitigation.status
  end

  private

  def steps
    [ { "kind" => "change", "description" => "Turn new-checkout off", "tool" => @disable.model_facing_name, "undo" => "Turn new-checkout back on" },
      { "kind" => "check", "description" => "Check checkout errors against normal" } ]
  end

  def plan_with_change!
    plan = Chat::Plan.make!(chat: @chat, made_by: @alice, goal: "Stop checkout errors", steps: steps)
    [ plan, plan.steps.first ]
  end

  def run_as_step!(step)
    step.plan.move_step!(step.position, status: Chat::Plan::Step::STATUS_RUNNING)
    turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
         .ruby_llm_tool_calls.create!(tool_call_id: "call_9", name: @disable.model_facing_name, arguments: ARGUMENTS)
    tool = Chat::Tools::Connection.new(turn, @disable)
    tool.call(tool_call: RubyLLM::ToolCall.new(id: "call_9", name: tool.name, arguments: ARGUMENTS), **ARGUMENTS.symbolize_keys)
    Chat::Mitigation.for_call(@chat, "call_9")
  end
end
