require "test_helper"

class WorkflowsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_publish_request_to_user).returns({ channel_id: "D1", message_id: "1.1" })
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:update_workflow_publish_request).returns({ success: true })
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_publish_answer_to_user).returns({})
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_all_clear).returns({})
  end

  def drafted(name = "Look around", by: @bob)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: by)
    workflow.open_draft!(by: by).update!(steps: [ { "id" => "look", "name" => "look", "kind" => "call_tool",
                                                    "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => {} } } ],
                                         trigger: { "kind" => "manual", "inputs" => [ { "key" => "query", "question" => "What to look for?", "default" => "db" } ] })
    workflow
  end

  def published(name = "Look around")
    workflow = drafted(name)
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    workflow.reload
  end

  test "without the workflows flag every page and action answers not found" do
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = drafted
    sign_in(users(:alice), @workspace)

    get halon_workflows_path, headers: inertia_headers
    assert_response :not_found
    get workflow_path(workflow), headers: inertia_headers
    assert_response :not_found
    post run_workflow_path(workflow)
    assert_response :not_found
    patch settings_workspace_workflows_path, params: { workflow_run_retention_days: 30 }
    assert_response :not_found
  end

  test "any member sees the workflows, their runs, the library and nothing waiting to publish" do
    workflow = published
    sign_in(users(:bob), @workspace)

    get halon_workflows_path, headers: inertia_headers

    assert_response :success
    row = inertia_props["workflows"].sole
    assert_equal [ workflow.id, "Look around", Workflow::STATE_LIVE, "By hand" ], row.values_at("id", "name", "state", "triggerWords")
    assert_equal [ "check_later", "probing_scan" ], inertia_props["templates"].map { |template| template["key"] }
    assert_empty inertia_props["publishRequests"]
  end

  test "a member makes a draft from the library, asks an admin to publish it, and the admin publishes it from the request" do
    sign_in(users(:bob), @workspace)
    post halon_workflows_path, params: { template: "probing_scan", time_zone: "Europe/Belgrade" }
    workflow = @workspace.workflows.find_by!(library_key: "probing_scan")
    assert_equal "Look for probing in the logs was made as a draft.", flash[:notice]

    post publish_workflow_path(workflow)
    assert_match "permission", flash[:alert]
    refute workflow.reload.live?

    post ask_publish_workflow_path(workflow)
    assert_match "to publish Look for probing in the logs.", flash[:notice]
    request = workflow.publish_requests.sole

    sign_in(users(:alice), @workspace)
    get halon_workflows_path, headers: inertia_headers
    assert_equal [ request.id ], inertia_props["publishRequests"].map { |shown| shown["id"] }
    post publish_workflow_publish_request_path(request)
    assert_equal "Look for probing in the logs was published.", flash[:notice]
    assert workflow.reload.live?
    assert_equal Time.zone.parse("09:00").hour, workflow.next_run_at.in_time_zone("Europe/Belgrade").hour
  end

  test "running by hand starts a run as the workflow and opens it, and a test run of the draft acts as the tester" do
    workflow = published
    sign_in(users(:bob), @workspace)

    perform_enqueued_jobs { post run_workflow_path(workflow), params: { inputs: { query: "api" } } }
    run = workflow.runs.find_by!(test: false)
    assert_redirected_to workflow_run_path(workflow, run)
    assert_equal "Look around is running.", flash[:notice]
    assert_equal({ "query" => "api" }, run.inputs)

    post test_run_workflow_path(workflow), params: { inputs: { query: "db" } }
    tested = workflow.runs.find_by!(test: true)
    assert_equal "A test run of Look around started.", flash[:notice]
    assert_equal @bob, tested.acting_principal
  end

  test "a run takes only the trigger's questions as plain answers, whatever else is sent" do
    workflow = published
    sign_in(users(:bob), @workspace)

    perform_enqueued_jobs { post run_workflow_path(workflow), params: { inputs: { query: { nested: "x" }, unasked: "y" } } }

    assert_equal({ "query" => "db" }, workflow.runs.sole.inputs)
  end

  test "the run page shows each step and pinning and stopping a run each say so" do
    workflow = published
    sign_in(users(:alice), @workspace)
    perform_enqueued_jobs { post run_workflow_path(workflow) }
    run = workflow.runs.sole

    get workflow_run_path(workflow, run), headers: inertia_headers
    assert_equal [ "look" ], inertia_props["run"]["steps"].map { |step| step["key"] }

    patch pin_workflow_run_path(workflow, run)
    assert_equal "This run is pinned, so it keeps its details.", flash[:notice]
    assert run.reload.pinned?
    patch unpin_workflow_run_path(workflow, run)
    assert_equal "This run is no longer pinned.", flash[:notice]

    post cancel_workflow_run_path(workflow, run)
    assert_equal "This run has already ended.", flash[:alert]
  end

  test "settings, on and off and deleting a workflow each say so, and one that ran is turned off rather than deleted" do
    workflow = published
    sign_in(users(:alice), @workspace)

    patch workflow_path(workflow), params: { cost_cap_cents: 200, runs_per_hour: 10, all_clear: true, freeze_behaviour: "wait" }
    assert_equal "Look around was updated.", flash[:notice]
    assert_equal [ 200, 10, true, "wait" ], workflow.reload.values_at(:cost_cap_cents, :runs_per_hour, :all_clear, :freeze_behaviour)

    patch disable_workflow_path(workflow)
    assert_equal "Look around is off.", flash[:notice]
    patch enable_workflow_path(workflow)
    assert_equal "Look around is on.", flash[:notice]

    perform_enqueued_jobs { post run_workflow_path(workflow) }
    delete workflow_path(workflow)
    assert_equal "Look around ran 1 time, and those runs stay readable. Turn it off instead.", flash[:alert]

    unused = drafted("Unused", by: @alice)
    delete workflow_path(unused)
    assert_equal "Unused was deleted.", flash[:notice]
    assert_nil Workflow.find_by(id: unused.id)
  end

  test "a one off that ran is listed with what is done and can be made to repeat" do
    sign_in(users(:alice), @workspace)
    travel_to Time.zone.parse("2026-10-13 12:00 UTC") do
      workflow = drafted
      workflow.draft.update!(trigger: { "kind" => "once_at", "at" => "2026-10-13T12:30", "time_zone" => "UTC", "inputs" => [] })
      WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
      travel 31.minutes
      perform_enqueued_jobs { WorkflowTriggerSweepJob.perform_now }

      get halon_workflows_path, headers: inertia_headers
      assert_equal [ workflow.id ], inertia_props["done"].map { |row| row["id"] }
      assert_equal 1, inertia_props["doneRuns"].size

      post repeat_workflow_path(workflow), params: { repeat: "days", days: [ 1, 2, 3, 4, 5 ], at: "09:00", time_zone: "UTC" }
      assert_equal "Look around now has a draft that runs every weekday at 09:00 (UTC). Publish it to start.", flash[:notice]
    end
  end

  test "Halon's suggestion is accepted into the draft or dismissed, each saying so" do
    workflow = published
    edit = workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { step_id: "look", changes: { config: { arguments: { query: "web" } } } },
                          by: nil, halon: true, reason: "The search named no service.")
    sign_in(users(:alice), @workspace)

    get workflow_path(workflow), headers: inertia_headers
    suggestion = inertia_props["workflow"]["suggestions"].sole
    assert_equal [ "Set arguments to {\"query\":\"web\"} on look." ], suggestion["changes"]

    post accept_workflow_suggestion_path(workflow, edit.change_set_id)
    assert_equal "Halon's suggestion was added to the draft of Look around. Publish it to use it.", flash[:notice]
    assert_equal({ "query" => "web" }, workflow.draft.steps.sole.dig("config", "arguments"))
  end

  test "an admin sets how long runs keep their details" do
    sign_in(users(:alice), @workspace)

    patch settings_workspace_workflows_path, params: { workflow_run_retention_days: 30 }

    assert_equal "Workflow runs now keep their details for 30 days.", flash[:notice]
    assert_equal 30, @workspace.reload.workflow_run_retention_days

    patch settings_workspace_workflows_path, params: { workflow_run_retention_days: 0 }
    assert_equal 30, @workspace.reload.workflow_run_retention_days
  end
end
