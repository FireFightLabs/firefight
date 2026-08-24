require "test_helper"

class Webhooks::DeactivationNotifierTest < ActiveSupport::TestCase
  setup do
    @webhook = webhooks(:active_webhook)
    @workspace = @webhook.workspace
  end

  test "posts a notice to the incidents channel" do
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")

    adapter = mock("adapter")
    adapter.expects(:post_message).with do |channel_id:, text:, blocks:|
      channel_id == "C_INCIDENTS" && text.include?(@webhook.name) && text.include?(@webhook.url) && blocks.nil?
    end
    WorkspaceAdapter.stubs(:for).with(@workspace).returns(adapter)

    Webhooks::DeactivationNotifier.notify(@webhook, reason: "delinquency_threshold")
  end

  test "skips the notice when the workspace has no incidents channel" do
    @workspace.update!(incidents_channel_id: nil)
    WorkspaceAdapter.expects(:for).never

    Webhooks::DeactivationNotifier.notify(@webhook, reason: "delinquency_threshold")
  end

  test "a failed post never raises out of delivery tracking" do
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")

    adapter = mock("adapter")
    adapter.stubs(:post_message).raises(AdapterError::Unavailable.new("slack down"))
    WorkspaceAdapter.stubs(:for).with(@workspace).returns(adapter)

    assert_nothing_raised do
      Webhooks::DeactivationNotifier.notify(@webhook, reason: "delinquency_threshold")
    end
  end
end
