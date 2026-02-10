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
    interaction = build_interaction

    stub_post_ephemeral

    result = Interactions::PreviewAnnouncementHandler.execute(interaction)

    assert_equal "clear", result[:response_action]
  end

  test "raises error if workspace not found" do
    interaction = build_interaction(team_id: "T_NONEXISTENT")

    assert_raises(ActiveRecord::RecordNotFound) do
      Interactions::PreviewAnnouncementHandler.execute(interaction)
    end
  end

  private

  def build_interaction(team_id: @workspace.platform_id)
    Interaction.new(
      type: "block_actions",
      team_id: team_id,
      user_id: "U12345678",
      channel_id: "C12345678",
      action_id: Slack::Identifiers::PREVIEW_ANNOUNCEMENT
    )
  end
end
