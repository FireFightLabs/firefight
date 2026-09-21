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

  test "another chat's saved results are out of reach" do
    other = @workspace.investigations.create!(
      subject: incidents(:active_major_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400
    )
    @workspace.chats.create!(owner: other, model: "claude-sonnet-4-5", provider: :anthropic)

    assert_match "Nothing has been saved", Chat::Tools::ReadResult.new(other.reload).execute(search: "req-8f2")
  end
end
