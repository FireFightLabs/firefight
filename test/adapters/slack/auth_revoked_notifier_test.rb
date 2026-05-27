require "test_helper"

class Slack::AuthRevokedNotifierTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.create!(
      platform:     "slack",
      platform_id:  "T#{SecureRandom.hex(8)}",
      name:         "Test Workspace",
      access_token: "xoxb-test-token",
      installed_at: Time.current
    )
  end

  test "emits structured warn log with workspace identity + error_code" do
    Rails.logger.expects(:warn).with(
      has_entries(
        event:        "slack.auth_revoked",
        workspace_id: @workspace.id,
        platform_id:  @workspace.platform_id,
        error_code:   "token_revoked"
      )
    )

    Slack::AuthRevokedNotifier.notify(@workspace, error_code: "token_revoked")
  end
end
