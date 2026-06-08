require "test_helper"

class FirefightAi::IncidentResponderTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @responder = FirefightAi::IncidentResponder.new(@workspace)
  end

  test "answer_question returns AI response text" do
    stub_ruby_llm_response("The incident is about a database connection pool issue.")

    answer = @responder.answer_question(@incident, question: "what's going on?")
    assert_equal "The incident is about a database connection pool issue.", answer
  end

  test "answer_question includes incident context in prompt" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    captured_prompt = nil

    mock_response = mock("response")
    mock_response.stubs(:content).returns("summary")

    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    @responder.answer_question(@incident, question: "what happened?")

    assert_includes captured_prompt, @incident.identifier
    assert_includes captured_prompt, @incident.name
    assert_includes captured_prompt, "what happened?"
  end

  test "answer_question includes Layer 2 narrative summary in prompt" do
    summary_stub = OpenStruct.new(content: "Team investigating db replica lag\nRollback considered")
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(summary_stub)

    captured_prompt = nil
    mock_response = mock("response")
    mock_response.stubs(:content).returns("answer")
    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    @responder.answer_question(@incident, question: "summarize")

    assert_includes captured_prompt, "Narrative Summary"
    assert_includes captured_prompt, "Team investigating db replica lag"
  end

  test "answer_question omits Narrative Summary section when no summary exists" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)

    captured_prompt = nil
    mock_response = mock("response")
    mock_response.stubs(:content).returns("answer")
    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)

    @responder.answer_question(@incident, question: "summarize")

    assert_not_includes captured_prompt, "Narrative Summary"
  end

  private

  def stub_ruby_llm_response(text)
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)

    mock_response = mock("response")
    mock_response.stubs(:content).returns(text)

    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.stubs(:ask).returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)
  end
end
