require "test_helper"

# What the confirmation and Slack say about a call's safeguards, and a scale down through the capability, which is a
# change customers feel whichever provider runs it.
class Chat::SafeguardsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @alice)
    @turn = Conversation::Turn.new(@conversation, asker: @alice)
    @chat = @conversation.chat_record
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    @row = northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    @row.store_fields!("project" => "shop")
    northflank.tools.create!(name: "api_request", description: "API", read_only: false, enabled: true,
                             params_schema: { "type" => "object", "properties" => { "method" => {}, "path" => {}, "body" => {} } })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web",
                                         name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current,
                                         details: { "instances" => 3 })
  end

  test "scaling a resource below what the map last read it running is a mitigation, kept with the default time" do
    call = pause!("scale", { "resource" => @web.id, "instances" => 1, "intent" => "Scale web down to cut the load" })

    Chat::Safeguards.prepare!(@turn, [ call ])

    mitigation = Chat::Mitigation.for_call(@chat, "call_1")
    assert_equal Chat::Mitigation::DEFAULT_MINUTES, mitigation.duration_minutes
    assert_equal "Scale web down to cut the load", mitigation.title
    assert_equal "Undo after 1 hour", Chat::Tools.confirmation(call).expires.first.label
  end

  test "scaling up, or a resource whose count the map does not hold, is not taken for one" do
    up = pause!("scale", { "resource" => @web.id, "instances" => 5 })
    Chat::Safeguards.prepare!(@turn, [ up ])
    assert_nil Chat::Mitigation.for_call(@chat, "call_1")

    @web.update!(details: {})
    unknown = pause!("scale", { "resource" => @web.id, "instances" => 1 }, id: "call_2")
    Chat::Safeguards.prepare!(@turn, [ unknown ])
    assert_nil Chat::Mitigation.for_call(@chat, "call_2")
  end

  test "the Slack confirmation lists what the call touches, offers when it is undone, and never allows a row write for the chat" do
    confirmation = Chat::Tools::Confirmation.new(
      tool_call_id: "call_1", question: "Execute write query?", intent: "Fix the currency", asked: [], status: :awaiting, target: nil, call: nil,
      safeguards: [ [ "Rows it changes", "42 rows of orders" ] ], expires: [ Chat::Tools::Expiry.new(value: "60", label: "Undo after 1 hour") ], for_chat: false
    )

    blocks = Slack::Messages::AgentConfirmation.build(conversation_id: "c1", confirmations: [ confirmation ])
    actions = blocks.find { |block| block[:type] == "actions" }[:elements]

    assert blocks.any? { |block| block.dig(:text, :text).to_s.include?("*Rows it changes:* 42 rows of orders") }
    assert_equal [ Identifiers::AGENT_CONFIRM, Identifiers::AGENT_CANCEL, Identifiers::AGENT_EXPIRY ], actions.map { |element| element[:action_id] }
    assert_equal "c1:call_1:60", actions.last.dig(:initial_option, :value)

    waiting = Slack::Messages::AgentConfirmation.build(conversation_id: "c1", confirmations: [ confirmation.with(status: :owner_asked, waiting_on: "Bob Jones") ])
    assert waiting.any? { |block| block.dig(:elements, 0, :text).to_s.include?("Waiting for Bob Jones to agree") }
  end

  test "picking when it is undone in Slack keeps the choice before Confirm" do
    call = pause!("scale", { "resource" => @web.id, "instances" => 1 })
    Chat::Safeguards.prepare!(@turn, [ call ])

    Interactions::AgentExpiryHandler.execute(Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id,
                                                             user_id: @alice.platform_user_id, action_id: Identifiers::AGENT_EXPIRY,
                                                             selected_value: "#{@conversation.id}:call_1:240"))

    assert_equal 240, Chat::Mitigation.for_call(@chat, "call_1").duration_minutes
  end

  private

  def pause!(name, arguments, id: "call_1")
    @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "").ruby_llm_tool_calls.create!(tool_call_id: id, name: name, arguments: arguments)
    @chat.request_decisions!([ id ])
    @chat.tool_calls.find_by!(tool_call_id: id)
  end
end
