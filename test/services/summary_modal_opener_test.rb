require "test_helper"

class SummaryModalOpenerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_statuses, :incident_severities, :incident_roles

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @user_id = "U12345678"
  end

  test "posts temp message and opens summary modal" do
    Slack::Client.expects(:post_message).with(
      workspace: @workspace,
      channel: @incident.slack_channel_id,
      text: ":writing_hand: <@#{@user_id}> is updating the incident summary...",
      blocks: nil
    ).returns({ ok: true, ts: "1234567890.123456", channel: @incident.slack_channel_id })
    stub_open_modal

    SummaryModalOpener.open(
      workspace: @workspace,
      incident: @incident,
      trigger_id: "12345.trigger",
      user_id: @user_id
    )
  end

  test "cleans up temp message when trigger expires" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    stub_delete_message

    assert_raises(AdapterError::TriggerExpired) do
      SummaryModalOpener.open(
        workspace: @workspace,
        incident: @incident,
        trigger_id: "12345.trigger",
        user_id: @user_id
      )
    end
  end

  test "suppresses delete errors during cleanup" do
    stub_post_message
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("expired"))
    Slack::Client.stubs(:delete_message).raises(Slack::Client::ApiError.new("delete failed"))

    assert_raises(AdapterError::TriggerExpired) do
      SummaryModalOpener.open(
        workspace: @workspace,
        incident: @incident,
        trigger_id: "12345.trigger",
        user_id: @user_id
      )
    end
  end
end
