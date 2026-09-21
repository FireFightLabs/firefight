require "test_helper"

class Chat::SavedResultTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @chat = @workspace.chats.create!(owner: investigation, model: "claude-sonnet-4-5", provider: :anthropic)
  end

  test "a result is kept whole under a short name the agent can say back" do
    first = @chat.saved_results.keep!(tool_name: "log_query", text: "a\nb\nc")
    second = @chat.saved_results.keep!(tool_name: "log_query", text: "d")

    assert_equal "result_1", first.handle
    assert_equal "result_2", second.handle
    assert_equal 3, first.line_count
    assert_equal "a\nb\nc", first.reload.content
  end

  test "what a tool said is the customer's data, so it is encrypted at rest" do
    saved = @chat.saved_results.keep!(tool_name: "log_query", text: "password=hunter2")

    stored = Chat::SavedResult.connection.select_value("SELECT content FROM chat_saved_results WHERE id = '#{saved.id}'")
    assert_no_match(/hunter2/, stored)
  end

  test "lines are read by number, the way the preview counts them" do
    saved = @chat.saved_results.keep!(tool_name: "log_query", text: (1..10).map { |number| "line #{number}" }.join("\n"))

    assert_equal [ [ 4, "line 4" ], [ 5, "line 5" ] ], saved.lines_between(4, 5)
    assert_equal [ [ 10, "line 10" ] ], saved.lines_between(10, 99)
  end

  test "a search finds lines whatever their case and gives the lines around each match" do
    saved = @chat.saved_results.keep!(tool_name: "log_query", text: "boot\nwarming\nERROR Timeout reached\nretrying\ndone")

    match = saved.matches("timeout", context: 1).sole

    assert_equal 3, match.line
    assert_equal [ [ 2, "warming" ], [ 3, "ERROR Timeout reached" ], [ 4, "retrying" ] ], match.lines
  end

  test "how much is handed over whole follows the window of the model that is running" do
    @chat.model.update!(context_window: 200_000)
    roomy = @chat.result_limit
    @chat.model.update!(context_window: 1_000_000)

    assert_operator Chat.find(@chat.id).result_limit, :>, roomy
  end

  test "a model whose window is unknown still gets a limit" do
    @chat.model.update!(context_window: nil)

    assert_operator @chat.result_limit, :>, 0
  end

  test "deleting a chat takes its saved results with it" do
    saved = @chat.saved_results.keep!(tool_name: "log_query", text: "a")

    @chat.destroy!

    assert_not Chat::SavedResult.exists?(saved.id)
  end
end
