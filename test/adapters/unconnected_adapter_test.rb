require "test_helper"

class UnconnectedAdapterTest < ActiveSupport::TestCase
  setup do
    @workspace = Workspace.sign_up!(name: "No Slack Co", user: users(:alice)).workspace
  end

  test "a workspace with no chat platform gets the unconnected adapter" do
    assert_instance_of UnconnectedAdapter, WorkspaceAdapter.for(@workspace)
    assert_instance_of UnconnectedAdapter, @workspace.adapter
  end

  test "every method in the platform contract refuses" do
    adapter = WorkspaceAdapter.for(@workspace)

    PlatformAdapter.public_instance_methods(false).each do |method_name|
      assert_raises(AdapterError::NotConnected, "#{method_name} should refuse") do
        adapter.public_send(method_name, channel_id: "C1", user_id: "U1", text: "hi")
      end
    end
  end

  test "a high level method a platform adds beyond the contract refuses the same way" do
    assert_raises(AdapterError::NotConnected) do
      WorkspaceAdapter.for(@workspace).post_incident_announcement(channel_id: "C1", incident: nil)
    end
  end

  test "the refusal is an AdapterError, so callers that rescue adapter errors keep working" do
    assert_operator AdapterError::NotConnected, :<, AdapterError
  end

  test "it never claims to answer a conversion, so it is not mistaken for an array" do
    assert_not WorkspaceAdapter.for(@workspace).respond_to?(:to_ary)
    assert_equal 1, [ WorkspaceAdapter.for(@workspace) ].flatten.size
  end

  test "the hourly token refresh skips a workspace with no chat platform" do
    @workspace.update_columns(token_expires_at: 1.minute.from_now)
    refreshed = []
    Slack::TokenManager.any_instance.stubs(:refresh_workspace).with { |workspace| refreshed << workspace.id }.returns(true)

    WorkspaceAdapter.refresh_expiring_credentials(buffer: 1.hour)

    assert_not_includes refreshed, @workspace.id
  end
end
