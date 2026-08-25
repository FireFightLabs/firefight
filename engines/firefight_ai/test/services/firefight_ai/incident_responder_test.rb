require "test_helper"

class FirefightAi::IncidentResponderTest < ActiveSupport::TestCase
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

  test "answer_question with scope_thread_ts builds a thread-only prompt" do
    member = workspace_memberships(:alice_workspace_one)
    parent_ts = "100.000"

    [
      [ parent_ts, nil, "kicking off thread topic" ],
      [ "100.1", parent_ts, "reply one" ],
      [ "100.2", parent_ts, "reply two with new finding" ]
    ].each do |ts, thread_ts, content|
      @incident.incident_transcript_messages.create!(
        workspace: @workspace, workspace_membership: member,
        message_id: ts, thread_id: thread_ts,
        platform_user_id: member.platform_user_id,
        content: content, posted_at: Time.at(ts.to_f)
      )
    end

    captured_prompt = nil
    mock_response = mock("response")
    mock_response.stubs(:content).returns("thread summary")
    mock_chat = mock("chat")
    mock_chat.stubs(:with_instructions).returns(mock_chat)
    mock_chat.expects(:ask).with { |prompt| captured_prompt = prompt; true }.returns(mock_response)
    RubyLLM.stubs(:chat).returns(mock_chat)
    FirefightAi::IncidentSummaryService.any_instance.expects(:fetch_or_refresh).never

    answer = @responder.answer_question(@incident, question: "summarize this thread", scope_thread_ts: parent_ts)

    assert_equal "thread summary", answer
    assert_includes captured_prompt, "Thread Messages"
    assert_includes captured_prompt, "kicking off thread topic"
    assert_includes captured_prompt, "reply one"
    assert_includes captured_prompt, "reply two with new finding"
    assert_not_includes captured_prompt, "Narrative Summary"
  end

  test "answer_question with scope_thread_ts returns sentinel when thread has no messages" do
    answer = @responder.answer_question(@incident, question: "summarize", scope_thread_ts: "999.999")
    assert_includes answer, "don't see any messages"
  end

  test "answer_question records Inference row with feature label" do
    FirefightAi::IncidentSummaryService.any_instance.stubs(:fetch_or_refresh).returns(nil)
    stub_ruby_llm_response("answer")

    assert_difference "Inference.count", 1 do
      @responder.answer_question(@incident, question: "what happened?")
    end

    inference = Inference.order(:created_at).last
    assert_equal "incident_catchup", inference.feature
    assert_equal @incident, inference.inferable
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
