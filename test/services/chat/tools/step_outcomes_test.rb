require "test_helper"

# Seen in a real chat, Halon checked whether ember-landing was a Cloudflare Pages project, Cloudflare answered that no
# such project exists, and the step showed a red cross before Halon listed Workers and found it there. A read the
# provider answered not found is kept as one, and anything else that failed stays a failure.
class Chat::Tools::StepOutcomesTest < ActiveSupport::TestCase
  NotThere = Class.new(Integrations::Error) { include Integrations::NotFound }

  PAGES_GET = "async () => { return await cloudflare.request({method:'GET', path:'/accounts/'+accountId+'/pages/projects/ember-landing'}); }".freeze
  PAGES_DELETE = "async () => { return await cloudflare.request({method:'DELETE', path:'/accounts/'+accountId+'/pages/projects/ember-landing'}); }".freeze
  NOT_FOUND = "Error: Cloudflare API error: 8000007: Project not found. The specified project name does not match any of your existing projects.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: member)
    @turn = Conversation::Turn.new(@conversation, asker: member)
    @chat = @conversation.chat_record

    cloudflare = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", slug: "cloudflare",
                                                 settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    cloudflare.integration_environments.create!
    @execute = cloudflare.tools.create!(name: "execute", description: "Call the API", enabled: true, read_only: false,
                                        params_schema: { "type" => "object", "properties" => { "code" => { "type" => "string" } } })

    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @reads = fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: {}, enabled: true, read_only: true)
    @writes = fake.tools.create!(name: "write_thing", description: "Writes", params_schema: {}, enabled: true, read_only: false)
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
  end

  test "a check Cloudflare answered not found is kept as not found, and the ledger still records an error with its words" do
    answer!(NOT_FOUND)

    call(@execute, code: PAGES_GET)

    saved = @chat.outcome_call("call_1")
    assert_equal [ true, Chat::StepOutcome::FAILURE_NOT_FOUND ], [ saved.failed, saved.failure_kind ]
    invocation = Ability::Invocation.find_by!(workspace: @workspace, action_key: @execute.action_key)
    assert_equal [ Ability::Invocation::OUTCOME_ERROR, NOT_FOUND ], [ invocation.outcome, invocation.error_summary ]
  end

  test "a change Cloudflare answered not found is a failure, and so is a check it answered with any other error" do
    answer!(NOT_FOUND)
    call(@execute, code: PAGES_DELETE)
    answer!("Error: Cloudflare API error: 10000: Authentication error")
    call(@execute, id: "call_2", code: PAGES_GET)

    assert_equal [ Chat::StepOutcome::FAILURE_ERROR ] * 2, %w[call_1 call_2].map { |id| @chat.outcome_call(id).failure_kind }
  end

  test "a provider's not found raised for a read is not found, and for a change is a failure" do
    Integrations::NativeExecutor.stubs(:call).raises(NotThere, "Fake answered 404: no such service")

    call(@reads)
    call(@writes, id: "call_2")

    assert_equal [ Chat::StepOutcome::FAILURE_NOT_FOUND, Chat::StepOutcome::FAILURE_ERROR ],
                 %w[call_1 call_2].map { |id| @chat.outcome_call(id).failure_kind }
  end

  test "a run keeps the not found on its step, which still counts as having run and can be cited" do
    investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    Ability::Grant.create!(workspace: @workspace, principal: investigation.acting_principal, action: @execute.reload.ability_action)
    Ability::Grant.create!(workspace: @workspace, principal: investigation.acting_principal, action: @reads.reload.ability_action)
    answer!(NOT_FOUND)
    Integrations::NativeExecutor.stubs(:call).raises(NotThere, "Fake answered 404: no such service")

    Chat::Tools::Connection.new(investigation, @execute).call(method: "GET", path: "/accounts/acc/pages/projects/ember-landing")
    Chat::Tools::Connection.new(investigation, @reads).call

    answered, raised = investigation.steps.ordered.to_a
    assert_equal [ Investigation::Step::STATUS_SUCCEEDED, Chat::StepOutcome::FAILURE_NOT_FOUND ], [ answered.status, answered.failure_kind ]
    assert_equal [ Investigation::Step::STATUS_FAILED, Chat::StepOutcome::FAILURE_NOT_FOUND ], [ raised.status, raised.failure_kind ]
    assert_equal Chat::StepOutcome::KIND_NOT_FOUND, Chat::StepOutcome.for_step(answered).kind
    assert investigation.record_hypothesis!(assertion: "ember-landing is a Worker", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
  end

  private

  def answer!(said)
    Integrations::McpExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => said } ], "isError" => true)
  end

  # The loop saves the model's call before running the tool. Here the call is saved by hand.
  def call(tool, id: "call_1", **arguments)
    llm_call = RubyLLM::ToolCall.new(id: id, name: tool.model_facing_name, arguments: arguments.stringify_keys)
    @chat.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { id => llm_call }))
    Chat::Tools::Connection.new(@turn, tool).call(tool_call: llm_call, **arguments)
  end
end
