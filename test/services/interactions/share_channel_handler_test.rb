require "test_helper"

class Interactions::ShareChannelHandlerTest < ActiveSupport::TestCase
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

  test "opens share modal and returns clear" do
    stub_open_modal

    result = Interactions::ShareChannelHandler.execute(build_interaction)

    assert_equal "clear", result[:response_action]
  end

  test "handles expired trigger" do
    stub_open_modal(raises: Slack::Client::TriggerExpiredError.new("Trigger expired"))

    result = Interactions::ShareChannelHandler.execute(build_interaction)

    assert_equal "errors", result[:response_action]
    assert result[:errors][:base].present?
    assert_includes result[:errors][:base], "expired"
  end

  private

  def build_interaction
    Interaction.new(
      type: "block_actions",
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      trigger_id: "12345.67890.trigger",
      action_id: Slack::Identifiers::SHARE_INCIDENTS_CHANNEL
    )
  end
end
