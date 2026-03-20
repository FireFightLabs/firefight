require "test_helper"

class IncidentAiServiceTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @service = IncidentAiService.new(@workspace)
  end

  test "answer_question returns AI response text" do
    stub_ruby_llm_response("The incident is about a database connection pool issue.")

    answer = @service.answer_question(@incident, question: "what's going on?")
    assert_equal "The incident is about a database connection pool issue.", answer
  end

  test "answer_question includes incident context in prompt" do
    captured_prompt = nil

    mock_response = mock("response")
    mock_response.stubs(:content).returns("summary")

    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    @service.answer_question(@incident, question: "what happened?")

    assert_includes captured_prompt, @incident.identifier
    assert_includes captured_prompt, @incident.name
    assert_includes captured_prompt, "what happened?"
  end

  test "answer_question includes transcript with thread structure" do
    alice = workspace_memberships(:alice_workspace_one)
    bob = workspace_memberships(:bob_workspace_one)

    grouped = [
      { at: "2026-03-20T10:00:00Z", by: alice.user.name, text: "Top level message", ts: "1000.000",
        replies: [
          { at: "2026-03-20T10:01:00Z", by: bob.user.name, text: "Thread reply", ts: "1001.000" }
        ] }
    ]
    IncidentTranscriptCache.stubs(:grouped_messages).returns(grouped)

    captured_prompt = nil
    mock_response = mock("response")
    mock_response.stubs(:content).returns("answer")
    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    @service.answer_question(@incident, question: "summarize")

    assert_includes captured_prompt, "Top level message"
    assert_includes captured_prompt, "(thread reply): Thread reply"
  end

  private

  def stub_ruby_llm_response(text)
    mock_response = mock("response")
    mock_response.stubs(:content).returns(text)

    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)
  end
end
