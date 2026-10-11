require "test_helper"

# A long tool says how far it got through RubyLLM's progress, and the loop hands each report to whoever listens, by the
# call's key, before the tool answers.
class FirefightAi::AgentLoopProgressTest < ActiveSupport::TestCase
  include FakeProviderHelper

  class Slow < RubyLLM::Tool
    description "Reads three pages"

    def name = "read_pages"

    def parameters_schema = { "type" => "object", "properties" => {} }

    def call(tool_call: nil, **)
      progress("Starting")
      Thread.new { progress("Page 2 of 3", value: 2, total: 3) }.join
      "three pages read"
    end
  end

  setup do
    FakeProviderHelper::Adapter.reset!
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @choice = FirefightAi::ModelChoice.new(model: "claude-haiku-4-5", provider: "anthropic", context: fake_provider_context(anthropic_api_key: "sk-ant-test"))
  end

  test "each report reaches the listener with the call's key, from the tool's own thread and any it starts" do
    chat = Chat.open!(owner: @conversation, workspace: @workspace, model_choice: @choice)
    FirefightAi.ready_chat(chat, choice: @choice, instructions: "Read.", tools: [ Slow.new ])
    chat.add_message(role: :user, content: "Read the pages")
    answer_with({ id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "tool_use",
                  content: [ { type: "tool_use", id: "toolu_9", name: "read_pages", input: {} } ], usage: { input_tokens: 5, output_tokens: 5 } })
    answer_with({ id: "msg_2", type: "message", role: "assistant", model: "claude-haiku-4-5", stop_reason: "end_turn",
                  content: [ { type: "text", text: "Done." } ], usage: { input_tokens: 9, output_tokens: 2 } })
    reports = []

    outcome = FirefightAi::AgentLoop.new(
      chat: chat, budget: FirefightAi::AgentLoop::Budget.new(max_spend_cents: 100, max_turns: 5), answered: -> { false }, reply_is_answer: true,
      inference: { workspace: @workspace, feature: "progress_test", provider: "anthropic", model: "claude-haiku-4-5" }, choice: @choice,
      on_progress: ->(progress) { reports << progress }
    ).run

    assert_equal FirefightAi::AgentLoop::STATUS_ANSWERED, outcome.status
    assert_equal [ [ "toolu_9", "Starting", nil, nil ], [ "toolu_9", "Page 2 of 3", 2, 3 ] ],
                 reports.map { |report| [ report.key, report.message, report.value, report.total ] }
  end
end
