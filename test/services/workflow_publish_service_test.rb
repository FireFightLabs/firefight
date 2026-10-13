require "test_helper"

class WorkflowPublishServiceTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @adapter = WorkspaceAdapter.for(@workspace).class
  end

  def drafted(name = "Look around")
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @bob)
    workflow.open_draft!(by: @bob).update!(steps: [ { "id" => "look", "name" => "look", "kind" => "call_tool",
                                                      "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => {} } } ])
    workflow
  end

  test "publishing makes the draft live, gives the workflow its own identity and grants it exactly what its steps need" do
    workflow = drafted

    result = WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)

    assert result.ok, result.words
    assert_equal "Look around was published.", result.words
    workflow.reload
    assert workflow.live?
    assert_equal "Look around workflow", workflow.agent.name
    grant = workflow.agent.ability_grants.sole
    assert_equal "incidents.read", grant.action.key
    assert_equal @alice, grant.granted_by
    assert_empty workflow.missing_reach
  end

  test "a draft with problems is not published and nothing is granted" do
    workflow = drafted
    workflow.draft.update!(steps: [ { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => "no_such_tool" } } ])

    result = WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)

    refute result.ok
    assert_equal "It cannot be published yet. look calls no_such_tool, which is not a tool in this workspace.", result.words
    assert_empty Ability::Grant.where(principal: workflow.reload.agent)
  end

  test "a member asks the admins to publish once a day, and publishing settles it and tells them" do
    workflow = drafted
    request = Workflow::PublishRequest.for!(@bob, workflow, workflow.draft)
    @adapter.any_instance.expects(:post_workflow_publish_request_to_user).with(has_entries(user_id: @alice.platform_user_id)).returns({ channel_id: "D1", message_id: "1.1" }).at_least_once

    asked = WorkflowPublishService.new(workflow).ask!(request, by: @bob)
    again = WorkflowPublishService.new(workflow).ask!(request, by: @bob)

    assert asked.ok, asked.words
    assert_match "Asked", asked.words
    assert_match "to publish Look around.", asked.words
    refute again.ok
    assert_match "they are not asked again until a day has passed", again.words
    assert_equal [ request ], workflow.publish_requests.waiting.to_a

    @adapter.any_instance.expects(:update_workflow_publish_request).with(has_entries(channel_id: "D1", message_id: "1.1"))
    @adapter.any_instance.expects(:post_workflow_publish_answer_to_user).with(has_entries(user_id: @bob.platform_user_id))
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)

    request.reload
    assert request.published_at
    assert_equal @alice, request.published_by
    assert_empty workflow.publish_requests.waiting
  end

  test "only the member who asked may ask again, and a request is dismissed once" do
    workflow = drafted
    request = Workflow::PublishRequest.for!(@bob, workflow, workflow.draft)

    assert_equal "Only #{@bob.display_name} can ask for this, since they asked first.", WorkflowPublishService.new(workflow).ask!(request, by: @alice).words

    @adapter.any_instance.stubs(:post_workflow_publish_answer_to_user).returns({})
    assert WorkflowPublishService.new(workflow).dismiss!(request, by: @alice).ok
    refute WorkflowPublishService.new(workflow).dismiss!(request, by: @alice).ok
  end
end
