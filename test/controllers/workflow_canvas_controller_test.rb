require "test_helper"

class WorkflowCanvasControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Probe check")
  end

  def delay(id, name = id) = { "id" => id, "name" => name, "kind" => DefinedWorkflow::KIND_DELAY, "config" => { "minutes" => 5 } }

  test "the canvas is not found for a workspace without the workflows flag" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow), headers: inertia_headers

    assert_response :not_found
  end

  test "the header says how many runs were skipped for the workflow's most runs an hour, and when" do
    @workflow.update!(runs_per_hour: 40)
    travel_to(Time.zone.parse("2026-10-14 14:05 UTC")) { 3.times { @workflow.run_skipped! } }
    sign_in(users(:bob), @workspace)

    travel_to Time.zone.parse("2026-10-14 16:00 UTC") do
      get workflow_path(@workflow), headers: inertia_headers
    end

    shown = inertia_props["workflow"]
    assert_equal 40, shown["runsPerHour"]
    assert_equal [ { "hour" => "2026-10-14T14:00:00Z", "count" => 3, "lastAt" => "2026-10-14T14:05:00Z" } ], shown["skippedRuns"]
    assert_equal "3 runs were skipped in the last week because it had already started as many runs in the hour before as it allows.", shown["skippedRunsSentence"]
  end

  test "a step that changes something says whether it can check first that it is still needed" do
    restart = { "id" => "restart", "name" => "restart", "kind" => "call_tool", "config" => { "tool" => "restart", "arguments" => { "resource" => "web" }, "check_first" => false } }
    post = { "id" => "tell", "name" => "tell", "kind" => "post_to_channel", "config" => { "channel" => "#ops", "message" => "Hi" } }
    @workflow.open_draft!(by: @alice).update!(steps: [ restart, post, delay("pause") ])
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow), headers: inertia_headers

    shown = inertia_props["document"]["steps"].to_h { |step| [ step["id"], step["checksFirst"] ] }
    assert_equal({ "restart" => true, "tell" => false, "pause" => false }, shown)
  end

  test "a new workflow shows an empty draft to start from, with the palette's kinds and triggers" do
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow), headers: inertia_headers

    assert_response :success
    document = inertia_props["document"]
    assert_not document["saved"]
    assert document["editable"]
    assert_equal [], document["steps"]
    assert_equal Workflow::Trigger::KIND_MANUAL, document["trigger"]["kind"]
    assert_equal "Run by hand", document["trigger"]["label"]
    kinds = inertia_props["stepKinds"].map { |kind| kind["key"] }
    assert_includes kinds, DefinedWorkflow::KIND_BRANCH
    DefinedWorkflow::Steps.kinds.each { |klass| assert_includes kinds, klass.kind }
    assert_equal Workflow::TriggerKinds.all.map(&:key), inertia_props["triggerKinds"].map { |kind| kind["key"] }
  end

  test "the draft shows each step with its kind, routes and who last changed it, and the history says who did what" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("wait", "wait_a_bit") }, by: @alice)
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: @alice,
                    payload: { "step" => { "id" => "decide", "name" => "decide", "kind" => DefinedWorkflow::KIND_BRANCH,
                                           "config" => { "routes" => [ { "route" => "yes", "when" => { "left" => "1", "operator" => "equals", "right" => "1" } } ], "otherwise" => "no" } } })
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow), headers: inertia_headers

    steps = inertia_props["document"]["steps"].index_by { |step| step["id"] }
    assert_equal [ "Wait a bit", "Delay", "reads" ], steps["wait"].values_at("title", "kindLabel", "effect")
    assert_equal [ "yes", "no" ], steps["decide"]["routes"]
    assert_not steps["decide"]["changedByHalon"]
    version = inertia_props["versions"].sole
    assert_equal "draft", version["status"]
    assert_equal [ "Alice Smith added Decide.", "Alice Smith added Wait a bit." ], version["edits"].map { |edit| edit["sentence"] }
  end

  test "an older version opens read only from the address" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("wait") }, by: @alice)
    first = @workflow.reload.draft
    first.publish!(by: @alice)
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("later") }, by: @alice)
    @workflow.reload.draft.publish!(by: @alice)
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow, version: first.id), headers: inertia_headers

    document = inertia_props["document"]
    assert_equal [ 1, "retired", false ], document.values_at("number", "status", "editable")
    assert_nil document["restoreBlockedReason"]
  end

  test "Halon's suggestions come with the old value beside the new, and Halon's changes with why they cannot be undone" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, payload: { "step" => delay("wait") }, by: @alice)
    @workflow.reload.draft.publish!(by: @alice)
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { "step_id" => "wait", "changes" => { "config" => { "minutes" => 30 } } },
                           by: nil, halon: true, reason: "Five minutes was too short in the last three runs.")
    sign_in(users(:bob), @workspace)

    get workflow_path(@workflow), headers: inertia_headers

    suggestion = inertia_props["suggestions"].sole
    assert_equal "Change Wait", suggestion["words"]
    assert_equal "Five minutes was too short in the last three runs.", suggestion["reason"]
    assert_equal [ { "field" => "Minutes", "before" => "5", "after" => "30" } ], suggestion["changes"]
  end
end
