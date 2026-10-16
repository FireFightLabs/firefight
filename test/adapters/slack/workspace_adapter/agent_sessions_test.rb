require "test_helper"

class Slack::WorkspaceAdapter::AgentSessionsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
  end

  test "an answer opens the agent session and streams into the thread where Slack allows it" do
    Slack::Client.expects(:set_agent_session_status).with { |arguments| arguments[:status] == "processing" }.returns({ ok: true })
    Slack::Client.expects(:start_stream).returns({ ok: true, ts: "9.9" })

    assert_equal "9.9", @adapter.start_agent_answer(channel_id: "C1", thread_id: "1.2", user_id: "U1")[:answer_id]
  end

  test "a workspace whose Slack refuses agent sessions is not asked again, nor asked to clear one, until a day has passed" do
    calls = []
    Slack::Client.stubs(:set_agent_session_status).with { |arguments| calls << arguments[:status] }.raises(AdapterError, "Slack API error: not_authorized")
    Slack::Client.expects(:start_stream).never

    assert_nil @adapter.start_agent_answer(channel_id: "C1", thread_id: "1.2", user_id: "U1")[:answer_id]
    @adapter.clear_agent_session(channel_id: "C1", thread_id: "1.2")
    later = Slack::WorkspaceAdapter.new(@workspace.reload)
    assert_nil later.start_agent_answer(channel_id: "C2", thread_id: "3.4", user_id: "U1")[:answer_id]
    later.clear_agent_session(channel_id: "C2", thread_id: "3.4")

    assert_equal [ "processing" ], calls

    travel 25.hours do
      Slack::WorkspaceAdapter.new(@workspace.reload).start_agent_answer(channel_id: "C1", thread_id: "5.6", user_id: "U1")
      assert_equal [ "processing", "processing" ], calls
    end
  end

  test "a refusal that may pass, such as a rate limit, is not remembered" do
    Slack::Client.stubs(:set_agent_session_status).raises(AdapterError::RateLimited.new(3))

    @adapter.start_agent_answer(channel_id: "C1", thread_id: "1.2", user_id: "U1")

    assert_nil @workspace.reload.platform_data.to_h["agent_sessions_refused_at"]
  end
end
