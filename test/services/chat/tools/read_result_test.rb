require "test_helper"

class Chat::Tools::ReadResultTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @chat = @workspace.chats.create!(owner: @investigation, model: "claude-sonnet-4-5", provider: :anthropic)
    @api = @chat.saved_results.keep!(
      tool_name: "log_query", text: (1..600).map { |number| "api line #{number}#{' req-8f2 timeout' if number == 450}" }.join("\n")
    )
    @worker = @chat.saved_results.keep!(
      tool_name: "log_query", text: (1..300).map { |number| "worker line #{number}#{' req-8f2 retry' if number == 120}" }.join("\n")
    )
    @tool = Chat::Tools::ReadResult.new(@investigation.reload)
  end

  test "a range of lines is read by number" do
    answer = @tool.execute(result: "result_1", from_line: 449, to_line: 451)

    assert_match "450  api line 450 req-8f2 timeout", answer
    assert_no_match(/api line 452/, answer)
  end

  test "a search gives the matching lines with the lines around them" do
    answer = @tool.execute(result: "result_1", search: "REQ-8F2")

    assert_match "450  api line 450 req-8f2 timeout", answer
    assert_match "449  api line 449", answer
  end

  test "a search with no result named looks through everything saved in the chat, which is how two logs are lined up" do
    answer = @tool.execute(search: "req-8f2")

    assert_match "result_1", answer
    assert_match "api line 450", answer
    assert_match "result_2", answer
    assert_match "worker line 120", answer
  end

  test "what is read back is still framed as data" do
    answer = @tool.execute(result: "result_1", from_line: 1, to_line: 2)

    assert answer.start_with?("<tool_result tool=\"log_query\" trust=\"untrusted\">")
  end

  test "a long range is handed over a page at a time, and says where to carry on" do
    answer = @tool.execute(result: "result_1", from_line: 1, to_line: 600)

    assert_match "api line #{Chat::Tools::ReadResult::PAGE_LINES}", answer
    assert_no_match(/api line #{Chat::Tools::ReadResult::PAGE_LINES + 1}\b/, answer)
    assert_match "from_line #{Chat::Tools::ReadResult::PAGE_LINES + 1}", answer
  end

  test "too many matches are counted rather than all shown" do
    answer = @tool.execute(result: "result_1", search: "api line")

    assert_match(/#{600 - Chat::Tools::ReadResult::MATCH_LIMIT} more matches/, answer)
  end

  test "a name that was never saved is said plainly, with the ones that were" do
    answer = @tool.execute(result: "result_9", search: "x")

    assert_match "result_9", answer
    assert_match "result_1", answer
  end

  test "a search that finds nothing says so rather than returning nothing" do
    assert_match "No lines", @tool.execute(search: "kafka")
  end

  # Seen on the bench, Halon read a helper's five lines, then read the same logs again for the detail behind them.
  test "everything a run's helper read is opened whole by the helper's name, a large result from where its own chat saved it" do
    helper = helper_that_read(@chat, [ [ "log_query", (1..300).map { |number| "checkout line #{number}#{' req-8f2 stuck' if number == 210}" }.join("\n"), 4 ],
                                       [ "list_deploys", "web d-91 at 13:58", 5 ] ])

    listed = @tool.execute(result: "helper_1")
    assert_match "helper_1_result_1 (step 4, log_query, 300 lines)", listed
    assert_match "helper_1_result_2 (step 5, list_deploys, 1 lines)", listed
    assert_match "210  checkout line 210 req-8f2 stuck", @tool.execute(result: "helper_1_result_1", from_line: 209, to_line: 211)
    assert_match "helper_1_result_1 line 210", @tool.execute(search: "req-8f2"), "a search of everything reaches what helpers read"
    assert_match "web d-91", @tool.execute(result: "helper_1", search: "d-91")
    assert_equal "web d-91 at 13:58", helper.reload.results.second.content
  end

  test "another chat's helpers are out of reach" do
    other = @workspace.investigations.create!(subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    other_chat = @workspace.chats.create!(owner: other, model: "claude-sonnet-4-5", provider: :anthropic)
    helper_that_read(other_chat, [ [ "log_query", "checkout req-9a1 stuck", 2 ] ])

    assert_match "Nothing is saved as helper_1", @tool.execute(result: "helper_1")
    assert_match "No lines", @tool.execute(search: "req-9a1")
  end

  test "another chat's saved results are out of reach" do
    other = @workspace.investigations.create!(
      subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @workspace.chats.create!(owner: other, model: "claude-sonnet-4-5", provider: :anthropic)

    assert_match "Nothing has been saved", Chat::Tools::ReadResult.new(other.reload).execute(search: "req-8f2")
  end

  private

  # A helper of chat whose own chat holds each read as the loop leaves it, the first one large enough that its own chat
  # saved it and handed over only a preview.
  def helper_that_read(chat, reads)
    check = Chat::Helpers::Check.new(title: "Logs", brief: "Read the logs", deep: false)
    helper = Chat::Helper.start!(chat: chat, tool_call_id: "call_1", checks: [ check ], since: 1.minute.ago).sole
    own = @workspace.chats.create!(owner: helper, model: "claude-haiku-4-5", provider: :anthropic)
    reads.each_with_index do |(tool, text, step), index|
      id = "h_#{index}"
      own.add_message(role: :assistant, content: "", tool_calls: { id => RubyLLM::ToolCall.new(id: id, name: tool, arguments: {}) })
      shown = if index.zero?
        FirefightAi::Evidence.preview(text, handle: own.saved_results.keep!(tool_name: tool, text: text, step: step).handle, read_with: Chat::SavedResult::READ_WITH)
      else
        text
      end
      own.add_message(role: :tool, content: FirefightAi::Evidence.frame(tool, shown, step: step), tool_call_id: id)
    end
    helper
  end
end
