require "test_helper"

class FirefightAi::IncidentSummaryServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member    = workspace_memberships(:alice_workspace_one)
    @incident  = incidents(:active_critical_ws1)
    @service   = FirefightAi::IncidentSummaryService.new(@workspace)
  end

  # Path 4: cold start (no prior summary)

  test "returns nil when transcript is empty" do
    assert_nil @service.fetch_or_refresh(@incident)
  end

  test "cache miss with messages performs full generate and creates summary row" do
    add_message(message_id: "1.001", content: "investigating db replica lag")
    add_message(message_id: "1.002", content: "rollback considered")
    stub_llm_response("- Team investigating replica lag\n- Rollback considered")

    summary = @service.fetch_or_refresh(@incident)

    assert_not_nil summary
    assert_includes summary.content, "replica lag"
    assert_equal "1.002", summary.summary_up_to_ts
    assert_not_nil summary.inference
    assert_equal FirefightAi::IncidentSummaryService::FEATURE_FULL, summary.inference.feature
  end

  # Path 1: no new messages

  test "no new messages returns existing summary without calling LLM" do
    add_message(message_id: "1.001", content: "first")
    seed_summary(content: "cached body", up_to_ts: "1.001", generated_at: 1.hour.ago)

    RubyLLM.expects(:chat).never

    result = @service.fetch_or_refresh(@incident)
    assert_equal "cached body", result.content
  end

  # Path 2: within freshness window (slight staleness OK)

  test "fresh window returns cached summary even with new messages" do
    add_message(message_id: "1.001", content: "first")
    add_message(message_id: "1.002", content: "second")
    seed_summary(content: "cached body", up_to_ts: "1.001", generated_at: 1.minute.ago)

    RubyLLM.expects(:chat).never

    result = @service.fetch_or_refresh(@incident)
    assert_equal "cached body", result.content
  end

  # Path 3: incremental refresh

  test "stale summary with new top-level message triggers incremental refresh" do
    add_message(message_id: "1.001", content: "first")
    seed_summary(content: "prior body", up_to_ts: "1.001", generated_at: 30.minutes.ago)
    add_message(message_id: "1.002", content: "fresh new context")

    stub_llm_response("updated body with fresh context")

    result = @service.fetch_or_refresh(@incident)
    assert_equal "updated body with fresh context", result.content
    assert_equal "1.002", result.summary_up_to_ts
    assert_equal FirefightAi::IncidentSummaryService::FEATURE_INCREMENTAL, result.inference.feature
  end

  test "thread reply bundles full thread context into incremental prompt" do
    add_message(message_id: "100.0", content: "parent point")
    add_message(message_id: "100.1", thread_id: "100.0", content: "first reply")
    seed_summary(content: "prior body", up_to_ts: "100.1", generated_at: 30.minutes.ago)
    add_message(message_id: "100.2", thread_id: "100.0", content: "second reply (new)")

    captured_prompt = nil
    stub_llm_capturing_prompt { |p| captured_prompt = p }

    @service.fetch_or_refresh(@incident)

    assert_includes captured_prompt, "parent point"
    assert_includes captured_prompt, "first reply"
    assert_includes captured_prompt, "second reply (new)"
  end

  test "stale summary with no actual delta does not call LLM" do
    add_message(message_id: "1.001", content: "first")
    seed_summary(content: "prior body", up_to_ts: "1.001", generated_at: 30.minutes.ago)

    RubyLLM.expects(:chat).never

    result = @service.fetch_or_refresh(@incident)
    assert_equal "prior body", result.content
  end

  # Error handling

  test "LLM error during cold-start records error inference and returns nil" do
    add_message(message_id: "1.001", content: "first")

    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:ask).raises(StandardError, "kaboom")
    RubyLLM.stubs(:chat).returns(chat)

    assert_difference "Inference.count", 1 do
      result = @service.fetch_or_refresh(@incident)
      assert_nil result
    end

    assert_equal Inference::STATUS_ERROR, Inference.order(:created_at).last.status
  end

  test "LLM error during incremental refresh falls back to existing summary" do
    add_message(message_id: "1.001", content: "first")
    seed_summary(content: "prior body", up_to_ts: "1.001", generated_at: 30.minutes.ago)
    add_message(message_id: "1.002", content: "new context")

    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:ask).raises(StandardError, "kaboom")
    RubyLLM.stubs(:chat).returns(chat)

    result = @service.fetch_or_refresh(@incident)
    assert_equal "prior body", result.content
  end

  private

  def add_message(message_id:, content:, thread_id: nil)
    @incident.incident_transcript_messages.create!(
      workspace: @workspace,
      workspace_membership: @member,
      message_id: message_id,
      thread_id: thread_id,
      platform_user_id: @member.platform_user_id,
      content: content,
      posted_at: Time.at(message_id.to_f)
    )
  end

  def seed_summary(content:, up_to_ts:, generated_at:)
    IncidentSummary.create!(
      incident: @incident,
      workspace: @workspace,
      content: content,
      summary_up_to_ts: up_to_ts,
      generated_at: generated_at,
      model: "claude-haiku-4-5"
    )
  end

  def stub_llm_response(text)
    response = OpenStruct.new(
      content: text,
      input_tokens: 100, output_tokens: 50,
      cache_read_tokens: 0, cache_write_tokens: 0,
      cost: 0.001, stop_reason: "end_turn", id: "msg_test"
    )

    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:ask).returns(response)
    RubyLLM.stubs(:chat).returns(chat)
  end

  def stub_llm_capturing_prompt
    response = OpenStruct.new(content: "stub", input_tokens: 0, output_tokens: 0, cost: 0)
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:ask).with do |prompt|
      yield prompt
      true
    end.returns(response)
    RubyLLM.stubs(:chat).returns(chat)
  end
end
