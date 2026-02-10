require "test_helper"

class Interactions::ShareModalSubmissionHandlerTest < ActiveSupport::TestCase
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

  test "shares to selected channels and returns clear" do
    stub_post_message

    result = Interactions::ShareModalSubmissionHandler.execute(
      build_interaction(conversations: [ "C11111111" ])
    )

    assert_equal "clear", result[:response_action]
  end

  test "returns error if no targets selected" do
    result = Interactions::ShareModalSubmissionHandler.execute(
      build_interaction(conversations: [])
    )

    assert_equal "errors", result[:response_action]
    assert result[:errors][:share_target_block].present?
    assert_includes result[:errors][:share_target_block], "at least one"
  end

  test "handles multiple targets" do
    Slack::Client.expects(:post_message).times(3).returns({ ok: true, ts: "123.456" })

    result = Interactions::ShareModalSubmissionHandler.execute(
      build_interaction(conversations: [ "C11111111", "C22222222", "D33333333" ])
    )

    assert_equal "clear", result[:response_action]
  end

  private

  def build_interaction(conversations: [ "C11111111" ])
    Interaction.new(
      type: "view_submission",
      team_id: @workspace.platform_id,
      user_id: "U12345678",
      callback_id: Slack::Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL,
      values: {
        "share_target_block" => {
          "share_target_select" => {
            "selected_conversations" => conversations
          }
        }
      }
    )
  end
end
