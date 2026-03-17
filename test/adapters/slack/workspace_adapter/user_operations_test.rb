require "test_helper"

class Slack::WorkspaceAdapter::UserOperationsTest < ActiveSupport::TestCase
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

  test "resolve_user_ids_from_handles resolves by slack username" do
    Slack::Client.expects(:list_users).with(workspace: @workspace).returns([
      { id: "U11111111", name: "nina", deleted: false, is_bot: false, profile: { display_name: "Nina" } }
    ])

    result = @adapter.resolve_user_ids_from_handles(handles: [ "nina" ])

    assert_equal [ "U11111111" ], result[:resolved_user_ids]
    assert_empty result[:unresolved_handles]
  end

  test "resolve_user_ids_from_handles returns unresolved handles" do
    Slack::Client.expects(:list_users).with(workspace: @workspace).returns([])

    result = @adapter.resolve_user_ids_from_handles(handles: [ "nina" ])

    assert_empty result[:resolved_user_ids]
    assert_equal [ "nina" ], result[:unresolved_handles]
  end
end
