require "test_helper"

# What the open chat's conversation costs the database for each kind of card placed among its steps. A chat holding many
# of one costs the same as a chat holding a few, since each kind is read for the whole stretch shown at once.
class AgentChatThreadQueriesTest < ActionDispatch::IntegrationTest
  include CodeQuestionTestHelper
  FEW = 2
  MANY = 12

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:bob), @workspace)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    @conversation.ask!("Why is checkout slow?")
    @chat = @conversation.chat_record
  end

  test "watch lines cost the same for many watches as for a few" do
    assert_flat { |count| count.times { watch_with_line } }
  end

  test "refusals for want of a pack cost the same for many packs as for a few" do
    assert_flat { |count| count.times { refusal } }
  end

  test "code changes that asked a question and paused cost the same for many steps as for a few" do
    assert_flat { |count| count.times { code_fix_step } }
  end

  test "helpers cost the same for many as for a few, each with steps and an answer kept aside" do
    assert_flat { |count| count.times { helper_with_steps } }
  end

  private

  def assert_flat
    yield FEW
    thread_queries
    few = thread_queries
    yield MANY - FEW
    assert_same_queries few, thread_queries
  end

  def thread_queries
    queries_sent { get agent_chat_url(@conversation), headers: inertia_partial_headers("agent/index", AgentChatsController::THREAD_PROPS) }.tap do
      assert_response :success
    end
  end

  def refusal
    connection = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank #{SecureRandom.hex(3)}")
    connection.tools.create!(name: "restart_service", read_only: false, enabled: true)
    request = Ability::PackRequest.for!(@member, connection.permission_packs.find_by!(pack: Ability::Role::PACK_CHANGES))
    Chat::PackRefusal.create!(chat: @chat, pack_request: request, tool_call_id: "call_#{SecureRandom.hex(3)}")
  end

  # A step whose coding agent asked a question and then paused at its spending limit.
  def code_fix_step
    key = "call_#{SecureRandom.hex(4)}"
    asking = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    asking.ruby_llm_tool_calls.create!(tool_call_id: key, name: FirefightTools::SEARCH_INCIDENTS, arguments: {})
    request = CodeAgent::Request.new(principal: @member, source: AbilityGateway::SOURCE_CONVERSATION, place: @conversation, tool_call_id: key)
    session, = CodeAgentSession.open!(workspace: @workspace, choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"),
                                      repository: "acme/api", request: request)
    pause = CodeAgentSession::Pause.create!(session: session, workspace: @workspace, conversation: @conversation, arguments: { "repo" => "acme/api" },
                                            repository: "acme/api", base: "main", copy_ref: "c" * 40, budget_micros: 2_000_000,
                                            resumable_until: 15.minutes.from_now, status: CodeAgentSession::Pause::STATUS_OFFERED)
    work = Chat::CodeFixProgress.start
    work.asked!(ask_question!(session, "Tag or commit?").to_h)
    work.paused!(pause.to_h)
    Chat::StepProgress.keep!(@chat, key, work, since: 1.hour.ago)
  end

  # A helper whose own chat read twice, the second answer too large to hand over and kept aside.
  def helper_with_steps
    key = "call_#{SecureRandom.hex(4)}"
    Chat::Helper.start!(chat: @chat, tool_call_id: key, since: Time.current,
                        checks: [ Chat::Helpers::Check.new(title: "Logs of web", brief: "Read web's errors", deep: false) ])
    helper = @chat.helpers.find_by!(tool_call_id: key)
    own = Chat.open!(owner: helper, workspace: @workspace, model_choice: FirefightAi::ModelChoice.new(model: "gpt-4o", provider: "openai"))
    asking = own.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    2.times do |read|
      call = asking.ruby_llm_tool_calls.create!(tool_call_id: "#{key}_#{read}", name: FirefightTools::SEARCH_INCIDENTS, arguments: { "query" => "web" })
      kept = own.saved_results.keep!(tool_name: FirefightTools::SEARCH_INCIDENTS, text: "INC-1\n" * 50) if read.positive?
      content = kept ? "[Too large to hand over, saved as #{kept.handle}. Read it with read_result.]" : "INC-1"
      call.update!(result: own.messages.create!(role: Chat::Message::ROLE_TOOL, content: content))
    end
  end

  def watch_with_line
    watch = Chat::Watch.create!(chat: @chat, workspace: @workspace, asker: @member, title: "release run #{SecureRandom.hex(2)}",
                                expires_at: 40.minutes.from_now, limit_basis: Chat::Watch::BASIS_HISTORY)
    watch.steps.create!(position: 0, label: "Release run", capability: Integrations::Capabilities::HISTORY, arguments: { "resource" => "firefight" },
                        run_url: "https://github.com/acme/firefight/actions/runs/46")
    watch.updates.create!(kind: Chat::Watch::Update::KIND_SLOW, text: "Taking longer than usual.")
  end
end
