require "test_helper"

# A turn of a chat someone started in a tracker's issue: it acts as Firefight's agent, and what it says is posted in the
# issue's session, each tool as an action and the answer as the response.
class Conversation::IssueTurnTest < ActiveSupport::TestCase
  class FakeResponder
    attr_accessor :options

    def initialize(conversation, reply:, steps: [], status: FirefightAi::AgentLoop::STATUS_ANSWERED, during: nil)
      @conversation = conversation
      @reply = reply
      @steps = steps
      @status = status
      @during = during
    end

    def run(**arguments)
      @arguments = arguments
      @steps.each { |step| arguments[:on_step].call(step) }
      @during&.call(arguments)
      @conversation.reload.chat.add_message(role: :assistant, content: @reply) if @reply
      FirefightAi::AgentLoop::Outcome.new(status: @status, turns_used: 1, spent_micros: 0)
    end

    def context = @arguments[:context]

    def ai_model = FirefightAi::ModelChoice.new(model: "gpt-4o", provider: nil)
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear issue sync",
      settings: { "server_url" => "https://mcp.linear.app/mcp", Integration::APP_SETTING => true })
    integration.integration_environments.create!.store_installation!("org-1")
    @conversation = Conversation.start_in_issue!(integration: integration, session_id: "session-1", title: "ENG-12 Checkout",
                                                 issue_key: "ENG-12", issue_url: "https://linear.app/acme/issue/ENG-12")
    @conversation.ask!("Why is checkout failing?", asker: @conversation.started_by)
    @said = []
    Integrations::AgentSessions::Linear.any_instance.stubs(:say).with { |session_id, activity| @said << [ session_id, activity ] }
    AppUrl.stubs(:options).returns(host: "ff.example.com", protocol: "https")
  end

  def responder(**options)
    fake = FakeResponder.new(@conversation, **options)
    FirefightAi::Responder.stubs(:new).with { |*, **given| fake.options = given }.returns(fake)
    fake
  end

  def run_turn = ConversationReplyJob.perform_now(@conversation.id, workspace_memberships(:alice_workspace_one).id)

  test "the turn acts as the agent, ledgers its model calls under no member, and is told where it was asked" do
    fake = responder(reply: "Checkout's database is out of connections.")
    Conversation::Tools.expects(:for).with { |turn, **| turn.asker == SystemAgent.investigator }.returns([])

    run_turn

    assert_nil fake.options[:member]
    assert_match "You were asked in Linear issue ENG-12 https://linear.app/acme/issue/ENG-12", fake.context
    assert_match "You act as #{SystemAgent.investigator.actor_display_name}", fake.context
  end

  test "each tool is an action, shown while it runs and kept with how it went, and the answer is the response" do
    responder(reply: "Checkout's database is out of connections.", steps: [
                FirefightAi::AgentLoop::Step.new(key: "call_1", tool: "search_incidents", status: :running, arguments: { "query" => "checkout" }),
                FirefightAi::AgentLoop::Step.new(key: "call_1", tool: nil, status: :done, arguments: nil)
              ])
    Conversation::Tools.stubs(:for).returns([])

    run_turn

    running, done, answer = @said.map(&:last)
    assert_equal [ Integrations::AgentSessions::ACTION, true, nil ], [ running.kind, running.ephemeral, running.result ]
    assert_equal [ Integrations::AgentSessions::ACTION, false, "Done" ], [ done.kind, done.ephemeral, done.result ]
    assert_equal running.action, done.action
    assert_equal [ Integrations::AgentSessions::RESPONSE, "Checkout's database is out of connections." ], [ answer.kind, answer.body ]
    assert_not @conversation.reload.answer_owed?
  end

  test "a stop from the issue ends the turn, which says so as its response" do
    @conversation.request_stop!
    Conversation::Tools.stubs(:for).returns([])

    run_turn

    assert_equal [ Integrations::AgentSessions::RESPONSE, Conversation::Runner::STOPPED ], [ @said.last.last.kind, @said.last.last.body ]
  end

  test "a change goes through the gateway as the agent, and one an approval rule holds is said under the answer with where it is decided" do
    Chat::Tools::LookFirst.stubs(:refusal).returns(nil)
    ConversationChannel.stubs(:broadcast_to)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Faylee", slug: "faylee",
                                             settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    faylee.integration_environments.create!
    tool = faylee.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: SystemAgent.investigator, action: tool.ability_action)
    @workspace.find_or_create_approval_policy!.policy_rules.create!(priority: 1, conditions: [], outcome: { "require" => { "role" => "admin", "count" => 1 } })
    Integrations::McpExecutor.expects(:call).never
    responder(reply: "Scaling web down needs an approval first.", during: lambda { |_|
      turn = Conversation::Turn.new(@conversation.reload, asker: @conversation.started_by)
      Chat::Tools::Connection.new(turn, tool).call(tool_call: stub(id: "call_2"), "code" => "scale web to 0")
    })
    Conversation::Tools.stubs(:for).returns([])

    run_turn

    held = @conversation.chat.held_calls.sole
    assert_equal SystemAgent.investigator, held.asker
    answer = @said.last.last.body
    assert_match "A call is waiting for approval. An approver decides under Gateway, Approvals in Firefight (https://ff.example.com", answer
    assert_match "/gateway/approvals), and it runs as soon as it is approved.", answer
    assert_no_match "/agent/", answer
  end

  test "a change that needs confirming asks in the issue with Confirm and Skip to pick there" do
    delivery = Conversation::IssueDelivery.new(@conversation)
    call = Struct.new(:name, :arguments, :tool_call_id).new("restart", {}, "call_3")
    Chat::Tools.stubs(:confirmation).returns(Chat::Tools::Confirmation.new(tool_call_id: "call_3", question: "Restart checkout?", intent: nil, asked: nil,
                                                                           status: nil, target: "Production", call: nil))

    delivery.confirm!([ call ])

    asked = @said.last.last
    assert_equal Integrations::AgentSessions::ELICITATION, asked.kind
    assert_match "- Restart checkout? on Production", asked.body
    assert_equal [ "Confirm", "Skip" ], asked.choices
    assert_match "Choose Confirm to go ahead or Skip to leave it.", asked.body
    assert_no_match "https://", asked.body
  end

  test "a turn that could not finish is the session's error" do
    Conversation::Delivery.give_up!(@conversation, Conversation::Delivery::FAILED)

    assert_equal Integrations::AgentSessions::ERROR, @said.last.last.kind
    assert_match Conversation::Delivery::FAILED, @said.last.last.body
  end

  test "a refused tool names the agent's missing grant and offers no pack" do
    turn = Conversation::Turn.new(@conversation, asker: @conversation.started_by)

    refusal = turn.refusal("linear.save_issue")

    assert_match "#{SystemAgent.investigator.actor_display_name}, the agent this chat acts as, has no grant for linear.save_issue", refusal
    assert_no_match "pack", refusal
  end
end
