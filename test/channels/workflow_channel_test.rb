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

  test "an id that is not a workflow is refused" do
    stub_connection(current_user: users(:bob))

    subscribe(id: SecureRandom.uuid)

    assert subscription.rejected?
  end
end
