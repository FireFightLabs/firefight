require "test_helper"

class WorkflowChannelTest < ActionCable::Channel::TestCase
  setup do
    @workflow = Workflow.create!(workspace: workspaces(:slack_workspace_one), name: "Release")
  end

  test "a member of the workflow's workspace who may read workflows follows its page" do
    stub_connection(current_user: users(:bob))

    subscribe(id: @workflow.id)

    assert subscription.confirmed?
    assert_has_stream WorkflowChannel.stream_name(@workflow.id)
  end

  test "someone outside the workflow's workspace is refused" do
    stub_connection(current_user: users(:bob))

    subscribe(id: Workflow.create!(workspace: workspaces(:slack_workspace_two), name: "Theirs").id)

    assert subscription.rejected?
  end

  test "a member who may not read workflows is refused, by the same rule the page uses" do
    stub_connection(current_user: users(:bob))
    AbilityGateway.stubs(:permitted?).returns(false)

    subscribe(id: @workflow.id)

    assert subscription.rejected?
  end

  test "a page that says when it was read is told only the parts said since, so it does not read the rest again" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    stub_connection(current_user: users(:bob))
    read_at = Time.current.to_f
    Workflow::LiveDelivery.say(@workflow.id, Workflow::LiveSignal::PART_RUNS)

    subscribe(id: @workflow.id, WorkflowChannel::READ_AT_PARAM => read_at)

    assert_equal [ { "part" => Workflow::LiveSignal::PART_RUNS } ], transmissions
  end

  test "a page read after the last change is told nothing when it starts listening" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    stub_connection(current_user: users(:bob))
    travel_to(1.minute.ago) { Workflow::LiveDelivery.say(@workflow.id, Workflow::LiveSignal::PART_CANVAS) }

    subscribe(id: @workflow.id, WorkflowChannel::READ_AT_PARAM => Time.current.to_f)

    assert subscription.confirmed?
    assert_empty transmissions
  end

  test "a page that does not say when it was read is told every part" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    stub_connection(current_user: users(:bob))

    subscribe(id: @workflow.id)

    assert_equal Workflow::LiveSignal::PARTS.values.map { |part| { "part" => part } }, transmissions
  end

  test "a page read longer ago than what was said is kept is told every part" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    stub_connection(current_user: users(:bob))

    subscribe(id: @workflow.id, WorkflowChannel::READ_AT_PARAM => (Workflow::LiveDelivery::SAID_KEPT + 1.minute).ago.to_f)

    assert_equal Workflow::LiveSignal::PARTS.values.map { |part| { "part" => part } }, transmissions
  end

  test "a page is told every part when the cache cannot say what changed" do
    stub_connection(current_user: users(:bob))
    Rails.cache.stubs(:read_multi).raises(IOError, "cache down")

    subscribe(id: @workflow.id, WorkflowChannel::READ_AT_PARAM => Time.current.to_f)

    assert_equal Workflow::LiveSignal::PARTS.values.map { |part| { "part" => part } }, transmissions
  end

  test "an id that is not a workflow is refused" do
    stub_connection(current_user: users(:bob))

    subscribe(id: SecureRandom.uuid)

    assert subscription.rejected?
  end
end
