require "test_helper"

class Slack::WorkspaceAdapter::IncidentModalsTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
    platform: "slack",
    platform_id: "T#{SecureRandom.hex(8)}",
    name: "Test Workspace",
    access_token: "xoxb-test-token",
    installed_at: Time.current,
    incidents_channel_id: "C12345678"
    )
    @adapter = Slack::WorkspaceAdapter.new(@workspace)
  end

  test "open_invite_responders_modal opens modal with incident" do
    incident = mock("incident")
    Slack::Modals::Invite.expects(:build).with(
      incident,
      selected_user_ids: [ "U11111111" ],
      private_metadata: nil
    ).returns({ type: "modal", callback_id: Identifiers::INVITE_RESPONDERS_MODAL })

    Slack::Client.expects(:open_modal).with do |**args|
      args[:workspace] == @workspace &&
        args[:trigger_id] == "12345.trigger" &&
        args[:view][:callback_id] == Identifiers::INVITE_RESPONDERS_MODAL
    end.returns({ ok: true })

    result = @adapter.open_invite_responders_modal(
      trigger_id: "12345.trigger",
      incident: incident,
      selected_user_ids: [ "U11111111" ]
    )

    assert result[:success]
  end
end
