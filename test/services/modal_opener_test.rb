require "test_helper"

class ModalOpenerTest < ActiveSupport::TestCase
  NOTICES = {
    cancel: "#{Slack::Emoji::CANCELED} is canceling the incident...",
    close: "#{Slack::Emoji::RESOLVED} is closing the incident...",
    escalate: "#{Slack::Emoji::ESCALATED} is escalating the incident...",
    reopen: "#{Slack::Emoji::REOPENED} is reopening the incident...",
    summary: "#{Slack::Emoji::SUMMARY} is updating the incident summary..."
  }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @user_id = "U12345678"
  end

  NOTICES.each do |kind, notice|
    test "#{kind} posts its placeholder and opens its modal" do
      emoji, rest = notice.split(" ", 2)
      Slack::Client.expects(:post_message).with(
        workspace: @workspace,
        channel: @incident.channel_id,
        text: "#{emoji} <@#{@user_id}> #{rest}",
        blocks: nil
      ).returns({ ok: true, ts: "1234567890.123456", channel: @incident.channel_id })
      stub_open_modal

      open(kind)
    end
  end

  # What an update will say is not the channel's until it is sent, so nothing is posted while it is written.
  test "a status update posts no placeholder and opens its modal with nothing to clean up" do
    Slack::Client.expects(:post_message).never
    Slack::Client.expects(:open_modal).with { |arguments| !arguments[:view][:private_metadata].to_s.include?("temp_message_ts") }.returns({ ok: true, view: { id: "V1" } })

    open(:update)
  end

  # The placeholder id comes back as :message_id. Reading the wrong key made this a silent no-op.
  test "deletes the placeholder when the trigger expires" do
    stub_post_message
    stub_open_modal(raises: AdapterError::TriggerExpired.new("expired"))
    Slack::Client.expects(:delete_message).with(
      workspace: @workspace, channel: @incident.channel_id, ts: "1234567890.123456"
    ).returns({ ok: true })

    assert_raises(AdapterError::TriggerExpired) { open(:close) }
  end

  test "suppresses delete errors during cleanup" do
    stub_post_message
    stub_open_modal(raises: AdapterError::TriggerExpired.new("expired"))
    Slack::Client.stubs(:delete_message).raises(AdapterError.new("delete failed"))

    assert_raises(AdapterError::TriggerExpired) { open(:close) }
  end

  private

  def open(kind)
    ModalOpener.open(
      kind,
      workspace: @workspace,
      incident: @incident,
      trigger_id: "12345.trigger",
      user_id: @user_id
    )
  end
end
