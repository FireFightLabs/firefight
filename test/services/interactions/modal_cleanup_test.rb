require "test_helper"

class Interactions::ModalCleanupTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @adapter = mock("adapter")
    @workspace.stubs(:adapter).returns(@adapter)
  end

  test "deletes the temp message when both coordinates are present" do
    metadata = ModalState::Result.new(
      incident_id: 1,
      temp_message_ts: "1700000000.000100",
      channel_id: "C12345"
    )

    @adapter.expects(:delete_message).with(channel_id: "C12345", message_id: "1700000000.000100").once

    Interactions::ModalCleanup.delete_temp_message(@workspace, metadata)
  end

  test "is a no-op when temp_message_ts is nil" do
    metadata = ModalState::Result.new(incident_id: 1, temp_message_ts: nil, channel_id: "C12345")

    @adapter.expects(:delete_message).never

    Interactions::ModalCleanup.delete_temp_message(@workspace, metadata)
  end

  test "is a no-op when channel_id is nil" do
    metadata = ModalState::Result.new(incident_id: 1, temp_message_ts: "1700000000.000100", channel_id: nil)

    @adapter.expects(:delete_message).never

    Interactions::ModalCleanup.delete_temp_message(@workspace, metadata)
  end

  test "is a no-op when both coordinates are blank strings" do
    metadata = ModalState::Result.new(incident_id: 1, temp_message_ts: "", channel_id: "")

    @adapter.expects(:delete_message).never

    Interactions::ModalCleanup.delete_temp_message(@workspace, metadata)
  end

  test "swallows AdapterError and logs without re-raising" do
    metadata = ModalState::Result.new(
      incident_id: 1,
      temp_message_ts: "1700000000.000100",
      channel_id: "C12345"
    )

    @adapter.expects(:delete_message).raises(AdapterError.new("network down"))

    Rails.logger.expects(:warn).with do |payload|
      payload[:event] == "interactions.modal_cleanup.delete_temp_failed" &&
        payload[:error].include?("network down")
    end

    assert_nothing_raised do
      Interactions::ModalCleanup.delete_temp_message(@workspace, metadata)
    end
  end
end
