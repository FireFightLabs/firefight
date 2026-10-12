require "test_helper"

# A change Halon paused on, as the dashboard card draws it: what will happen first, where quieter under it, what it does,
# when it is undone and the button named for it, with the call itself kept for Details.
class AgentChatConfirmationSerializerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @chat = @conversation.chat_record
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
    northflank.integration_environments.create!(credentials: { token: "x" }.to_json).store_fields!("project" => "faylee")
    @tool = northflank.tools.create!(name: "api_request", description: "API", read_only: false, enabled: true, params_schema: { "type" => "object" })
  end

  PAUSE = { "method" => "POST", "path" => "services/dev-web/pause", "short_title" => "Pause dev-web",
            "intent" => "Pause the dev-web service so it stops running and stops billing, as you asked" }.freeze

  test "a change leads with the agent's few words, with what the tool reaches under them and its sentence after" do
    shown = shown(ask!(PAUSE))

    assert_equal "Pause dev-web", shown[:title]
    assert_equal "Faylee (Northflank), project faylee", shown[:label]
    assert_equal "Pause the dev-web service so it stops running and stops billing, as you asked.", shown[:summary]
    assert_equal "Pause dev-web", shown[:confirmLabel]
    assert_equal [ %w[method POST], %w[path services/dev-web/pause] ], shown[:asked].sort, "the agent's words for the person never show as arguments"
    assert_equal @tool.model_facing_name, shown[:tool]
    assert shown[:allowable]
    assert_nil shown[:undoLabel]
    assert_empty shown[:expires]
  end

  test "a call asked before short titles leads with the agent's sentence and approves with Confirm" do
    shown = shown(ask!(PAUSE.except("short_title")))

    assert_equal "Pause the dev-web service so it stops running and stops billing, as you asked", shown[:title]
    assert_nil shown[:summary]
    assert_equal Chat::Tools::CONFIRM, shown[:confirmLabel]

    without_words = shown(ask!(PAUSE.except("short_title", "intent"), id: "call_2"))
    assert_equal "Api request", without_words[:title]
    assert_equal "Faylee (Northflank), project faylee", without_words[:label]
  end

  test "a change customers feel offers its undo times in order from never, labelled for what undoing it means" do
    call = ask!(PAUSE)
    Chat::Mitigation.create!(chat: @chat, workspace: @workspace, tool_call_id: call.tool_call_id, tool_name: @tool.model_facing_name, action_key: @tool.action_key,
                             arguments: PAUSE.slice("method", "path"), duration_minutes: Chat::Mitigation::DEFAULT_MINUTES)

    shown = shown(call)

    assert_equal [ [ Chat::Mitigation::KEEP, "Never" ], [ "15", "15 min" ], [ "60", "1 h" ], [ "240", "4 h" ], [ "1440", "24 h" ] ],
                 shown[:expires].map { |expiry| expiry.values_at(:value, :label) }
    assert_equal "60", shown[:chosenExpiry]
    assert_equal Integrations::Mitigations::STARTS_AGAIN, shown[:undoLabel]

    Chat::Mitigation.find_by!(chat: @chat, tool_call_id: call.tool_call_id).update!(duration_minutes: nil, arguments: { "method" => "POST", "path" => "addons/x" })
    kept = shown(call)
    assert_equal Chat::Mitigation::KEEP, kept[:chosenExpiry]
    assert_equal Chat::Tools::UNDO_AUTOMATICALLY, kept[:undoLabel]
  end

  test "a change a running plan step carries out says how that step puts it back" do
    plan = Chat::Plan.make!(chat: @chat, made_by: @member, goal: "Stop paying for dev-web", steps: [
      { "kind" => "change", "description" => "Pause dev-web", "tool" => @tool.model_facing_name, "undo" => "Resume dev-web with one instance" },
      { "kind" => "check", "description" => "Check web still answers" }
    ])
    plan.move_step!(1, status: Chat::Plan::Step::STATUS_RUNNING)

    assert_equal "Pause the dev-web service so it stops running and stops billing, as you asked. To put it back: Resume dev-web with one instance.",
                 shown(ask!(PAUSE))[:summary]
  end

  test "the reads Halon named are points, what each showed with the read it came from" do
    @chat.messages.create!(role: Chat::Message::ROLE_USER, content: "dev-web costs too much")
    read = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = read.ruby_llm_tool_calls.create!(tool_call_id: "call_read", name: Integrations::Capabilities.spec(Integrations::Capabilities::METRICS).tool_name,
                                            arguments: { "resource" => "dev-web" })
    call.update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: "memory 100%"))

    shown = shown(ask!(PAUSE.merge("because" => [ "#{call.name}: dev-web memory pinned at 100%" ])))

    assert_equal Chat::Tools::SUPPORT_LEAD, shown[:supportLead]
    assert_equal [ { text: "dev-web memory pinned at 100%", source: Chat::Tools.label(call.name, call.arguments, workspace: @workspace) } ], shown[:supportPoints]
  end

  private

  def ask!(arguments, id: "call_1")
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: id, name: @tool.model_facing_name, arguments: arguments)
    @chat.request_decisions!([ id ])
    Chat::Tools::Target.record!(Conversation::Turn.new(@conversation, asker: @member), [ call ])
    call.reload
  end

  def shown(call) = AgentChatConfirmationSerializer.one(call)
end
