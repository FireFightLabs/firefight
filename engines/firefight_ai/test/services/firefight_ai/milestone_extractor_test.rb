require "test_helper"

class FirefightAi::MilestoneExtractorTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @extractor = FirefightAi::MilestoneExtractor.new(@workspace)
  end

  test "returns a milestone per row the model produced" do
    messages = [
      add_message(message_id: "1.001", content: "checkout is 500ing for EU only"),
      add_message(message_id: "1.002", content: "rolling back the 14:02 deploy")
    ]
    stub_model([
      { kind: "impact", statement: "Checkout is down for EU customers only", message_id: "1.001", confidence: 0.9 },
      { kind: "mitigation", statement: "Alice rolled back the 14:02 deploy", message_id: "1.002", confidence: 0.95 }
    ])

    milestones = @extractor.extract(@incident, messages: messages)

    assert_equal %w[impact mitigation], milestones.map(&:kind)
    assert_equal "Alice rolled back the 14:02 deploy", milestones.last.statement
    assert_equal "1.002", milestones.last.message_id
  end

  test "drops rows below the confidence floor" do
    messages = [ add_message(message_id: "1.001", content: "maybe the cache?") ]
    stub_model([
      { kind: "hypothesis", statement: "Alice suspects the cache", message_id: "1.001", confidence: 0.4 }
    ])

    assert_empty @extractor.extract(@incident, messages: messages)
  end

  test "drops rows naming a kind the timeline does not have" do
    messages = [ add_message(message_id: "1.001", content: "anything") ]
    stub_model([
      { kind: "vibes", statement: "Something happened", message_id: "1.001", confidence: 0.99 }
    ])

    assert_empty @extractor.extract(@incident, messages: messages)
  end

  test "drops rows citing a message that was never sent" do
    messages = [ add_message(message_id: "1.001", content: "real message") ]
    stub_model([
      { kind: "finding", statement: "Alice confirmed the pool is exhausted", message_id: "9.999", confidence: 0.99 }
    ])

    assert_empty @extractor.extract(@incident, messages: messages)
  end

  test "an empty transcript costs nothing" do
    RubyLLM.expects(:chat).never

    assert_empty @extractor.extract(@incident, messages: [])
  end

  test "records one inference with the milestones feature and exposes it" do
    messages = [ add_message(message_id: "1.001", content: "rolled back") ]
    stub_model([
      { kind: "mitigation", statement: "Alice rolled back the deploy", message_id: "1.001", confidence: 0.9 }
    ])

    assert_difference "Inference.count", 1 do
      @extractor.extract(@incident, messages: messages)
    end

    inference = Inference.find_by!(feature: FirefightAi::MilestoneExtractor::FEATURE, inferable: @incident)
    assert_equal Inference::STATUS_SUCCESS, inference.status
    assert_equal inference, @extractor.last_inference
  end

  test "the prompt carries the summary and the sentences already on the timeline" do
    messages = [ add_message(message_id: "1.001", content: "db replica 2 is out of connections") ]
    captured = nil
    stub_model([], &->(prompt) { captured = prompt })

    @extractor.extract(
      @incident,
      messages: messages,
      summary: IncidentSummary.new(content: "Team is chasing replica lag"),
      timeline: [ "escalated the incident to Bob" ]
    )

    assert_includes captured, "Team is chasing replica lag"
    assert_includes captured, "escalated the incident to Bob"
    assert_includes captured, "db replica 2 is out of connections"
    assert_includes captured, "[1.001]"
  end

  test "an oversized transcript keeps the newest messages and still runs" do
    filler = "x" * (FirefightAi::MilestoneExtractor::MAX_INPUT_TOKENS * FirefightAi::MilestoneExtractor::CHARS_PER_TOKEN)
    messages = [
      add_message(message_id: "1.001", content: filler),
      add_message(message_id: "1.002", content: "root cause was the migration lock")
    ]
    captured = nil
    stub_model([], &->(prompt) { captured = prompt })

    @extractor.extract(@incident, messages: messages)

    assert_includes captured, "root cause was the migration lock"
    assert_not_includes captured, "[1.001]"
  end

  test "client errors leave the engine as its own error family" do
    messages = [ add_message(message_id: "1.001", content: "anything") ]
    RubyLLM.stubs(:chat).raises(RubyLLM::RateLimitError.new("slow down"))

    error = assert_raises(FirefightAi::TransientError) { @extractor.extract(@incident, messages: messages) }
    assert_equal "RateLimitError", error.reason
  end

  private

  def add_message(message_id:, content:)
    @incident.incident_transcript_messages.create!(
      workspace: @workspace,
      workspace_membership: @member,
      message_id: message_id,
      platform_user_id: @member.platform_user_id,
      content: content,
      posted_at: Time.at(message_id.to_f)
    )
  end

  def stub_model(rows, &capture)
    response = OpenStruct.new(
      content: { "milestones" => rows.map(&:stringify_keys) },
      input_tokens: 100, output_tokens: 50,
      cache_read_tokens: 0, cache_write_tokens: 0,
      cost: 0.0001, stop_reason: "end_turn", id: "msg_test"
    )

    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_schema).returns(chat)
    if capture
      chat.stubs(:ask).with { |prompt| capture.call(prompt); true }.returns(response)
    else
      chat.stubs(:ask).returns(response)
    end
    RubyLLM.stubs(:chat).returns(chat)
  end
end
