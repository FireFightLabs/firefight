require "test_helper"

class Workflow::LiveDeliveryTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  PART = Workflow::LiveSignal::PART_CANVAS

  setup do
    # The test environment caches nothing, and the window lives in the cache.
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @workflow = Workflow.create!(workspace: workspaces(:slack_workspace_one), name: "Release")
    @stream = WorkflowChannel.stream_name(@workflow.id)
    Rails.cache.clear
    pubsub_adapter.clear_messages(@stream)
  end

  test "a storm of changes to one part is said once at once and once after the window" do
    assert_enqueued_jobs 1, only: WorkflowPageSignalJob do
      20.times { Workflow::LiveDelivery.changed(workflow_id: @workflow.id, part: PART) }
    end
    assert_broadcasts @stream, 1

    travel Workflow::LiveDelivery::WINDOW * 2 do
      perform_enqueued_jobs(only: WorkflowPageSignalJob)
    end

    assert_broadcasts @stream, 2
  end

  test "a delivery that fails is logged and never fails the change that committed" do
    ActionCable.server.stubs(:broadcast).raises(IOError, "cable down")

    assert_nothing_raised { @workflow.update!(description: "Committed.") }
    assert_equal "Committed.", @workflow.reload.description
  end
end
