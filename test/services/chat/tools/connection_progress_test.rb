require "test_helper"

class Chat::Tools::ConnectionProgressTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    member = workspace_memberships(:alice_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: member)
    @turn = Conversation::Turn.new(@conversation, asker: member)
    @chat = @conversation.chat_record
    fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake")
    fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @tool = fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: {}, enabled: true, read_only: true)
    Integrations::NativePack.stubs(:for).with("fake").returns(FakeNativePack)
  end

  test "a call's progress reaches the turn under the call's own id" do
    heard = []
    @turn.listen_to_progress { |key, update| heard << [ key, update ] }
    work = Chat::CodeFixProgress.start
    Integrations::NativeExecutor.stubs(:call).with { |progress:, **| progress.call(work) }.returns("content" => [ { "type" => "text", "text" => "ok" } ])

    call("call_9")

    assert_equal [ [ "call_9", work ] ], heard
  end

  test "a call made with nobody listening runs as before" do
    Integrations::NativeExecutor.expects(:call).with { |progress:, **| progress.nil? }.returns("content" => [ { "type" => "text", "text" => "ok" } ])

    call("call_9")
  end

  private

  def call(id)
    llm_call = RubyLLM::ToolCall.new(id: id, name: @tool.model_facing_name, arguments: {})
    @chat.add_message(RubyLLM::Message.new(role: :assistant, content: "", tool_calls: { id => llm_call }))
    Chat::Tools::Connection.new(@turn, @tool).call(tool_call: llm_call)
  end
end
