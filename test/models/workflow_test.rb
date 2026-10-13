require "test_helper"

class WorkflowTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "takes a slug from its name and tidies its other names" do
    workflow = Workflow.create!(workspace: @workspace, name: "  Release   firefight ", aliases: [ "ship it", "Ship It", " ", "deploy" ],
                                description: "releases the app")

    assert_equal "Release firefight", workflow.name
    assert_equal "release_firefight", workflow.slug
    assert_equal [ "ship it", "deploy" ], workflow.aliases
    assert_equal "Releases the app.", workflow.description
    assert workflow.enabled?
    assert_nil workflow.cost_cap_cents, "a new workflow has no cost cap"
    assert_nil workflow.agent
  end

  test "is found by its slug, its name or another name, whatever the case" do
    workflow = Workflow.create!(workspace: @workspace, name: "Release firefight", aliases: [ "Ship it" ])
    scope = Workflow.where(workspace: @workspace)

    assert_equal workflow, Workflow.named(scope, "release_firefight")
    assert_equal workflow, Workflow.named(scope, "RELEASE FIREFIGHT")
    assert_equal workflow, Workflow.named(scope, "ship it")
    assert_nil Workflow.named(scope, "something else")
    assert_nil Workflow.named(Workflow.where(workspace: workspaces(:slack_workspace_two)), "ship it")
  end

  test "an owner is a team on this workspace's catalog" do
    assert Workflow.new(workspace: @workspace, name: "Owned", owner_team: catalog_entries(:platform_team)).valid?

    service = Workflow.new(workspace: @workspace, name: "Owned", owner_team: catalog_entries(:auth_service))
    assert_not service.valid?
    assert_includes service.errors[:owner_team], "must be a team on the catalog"
  end

  test "a cost cap is a positive number of cents when set" do
    assert_not Workflow.new(workspace: @workspace, name: "Capped", cost_cap_cents: 0).valid?
    assert Workflow.new(workspace: @workspace, name: "Capped", cost_cap_cents: 500).valid?
  end

  test "a run cannot start without the workflows flag, when off, or with nothing published" do
    workflow = Workflow.create!(workspace: @workspace, name: "Check")
    assert_equal "Workflows are not switched on for this workspace.", workflow.start_blocked_reason

    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    assert_equal "Check has no published version to run.", workflow.start_blocked_reason

    draft = workflow.open_draft!(by: @alice)
    draft.update!(steps: [ { "id" => "pause", "name" => "pause", "kind" => "delay", "config" => { "seconds" => 1 } } ])
    draft.publish!(by: @alice)
    assert_nil workflow.reload.start_blocked_reason

    workflow.update!(enabled: false)
    assert_equal "Check is switched off.", workflow.start_blocked_reason
  end
end
