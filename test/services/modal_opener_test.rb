require "test_helper"

class ModalOpenerTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incidents,
           :incident_lifecycle_stages, :incident_statuses, :incident_severities, :incident_roles,
           :incident_forms, :incident_form_fields, :catalog_types, :incident_field_definitions, :incident_field_options

  NOTICES = {
    cancel: ":wastebasket: is canceling the incident...",
    close: ":lock: is closing the incident...",
    escalate: ":rotating_light: is escalating the incident...",
    reopen: ":rotating_light: is reopening the incident...",
    summary: ":writing_hand: is updating the incident summary...",
    update: ":writing_hand: is writing an internal status update..."
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

  # The placeholder id comes back as :message_id, and reading the wrong key made
  # this cleanup a silent no-op that left an orphaned message in the channel.
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
