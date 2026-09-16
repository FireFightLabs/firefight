require "test_helper"

class Events::AgentSessionStoppedHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
      max_turns: 10, max_spend_cents: 400, thread_id: "1700000000.000100"
    )
    @investigation.claim!
  end

  test "pressing stop asks the run to end" do
    Events::AgentSessionStoppedHandler.execute(@workspace, payload(thread_ts: "1700000000.000100"))

    assert @investigation.reload.cancel_requested?
  end

  test "a thread with no run behind it is ignored" do
    assert_nothing_raised do
      Events::AgentSessionStoppedHandler.execute(@workspace, payload(thread_ts: "1700000000.999999"))
    end
    assert_not @investigation.reload.cancel_requested?
  end

  test "a run that already finished is left alone" do
    @investigation.finish!(status: Investigation::STATUS_SUCCEEDED)

    Events::AgentSessionStoppedHandler.execute(@workspace, payload(thread_ts: "1700000000.000100"))

    assert_not @investigation.reload.cancel_requested?
  end

  private

  def payload(thread_ts:)
    { "team_id" => @workspace.platform_id, "event" => { "type" => Identifiers::EVENT_AGENT_SESSION_STOPPED, "thread_ts" => thread_ts } }
  end
end
