require "test_helper"

class Interactions::PreviewAnnouncementHandlerTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform: "slack",
      platform_id: "T#{SecureRandom.hex(8)}",
      name: "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current,
      incidents_channel_id: "C12345678"
    )
  end

  test "posts ephemeral preview message and returns clear" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "block_actions",
      overrides: {
        "actions" => [ { "action_id" => Slack::Identifiers::PREVIEW_ANNOUNCEMENT } ]
      }
    )

    stub_post_ephemeral

    result = Interactions::PreviewAnnouncementHandler.execute(payload)

    assert_equal "clear", result[:response_action]
  end

  test "raises error if workspace not found" do
    payload = mock_slack_interaction_payload(
      team_id: @workspace.platform_id,
      type: "block_actions",
      overrides: { "team" => { "id" => "T_NONEXISTENT" } }
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      Interactions::PreviewAnnouncementHandler.execute(payload)
    end
  end
end
