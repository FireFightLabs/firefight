require "test_helper"

class WorkflowsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_publish_request_to_user).returns({ channel_id: "D1", message_id: "1.1" })
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:update_workflow_publish_request).returns({ success: true })
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_publish_answer_to_user).returns({})
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_all_clear).returns({})
  end

  def drafted(name = "Look around", by: @bob)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: by)
    workflow.open_draft!(by: by).update!(steps: [ { "id" => "look", "name" => "look", "kind" => "call_tool",
                                                    "config" => { "tool" => FirefightTools::SEARCH_INCIDENTS, "arguments" => {} } } ],
                                         trigger: { "kind" => "manual", "inputs" => [ { "key" => "query", "question" => "What to look for?", "default" => "db" } ] })
    workflow
  end

  def published(name = "Look around")
    workflow = drafted(name)
    WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @alice)
    workflow.reload
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

  test "the page says whether the person may make workflows, which a member holds by default and an admin can take away" do
    sign_in(users(:bob), @workspace)
    get halon_workflows_path, headers: inertia_headers
    assert inertia_props["canCreate"]

    Ability::Grant.withhold!(workspace: @workspace, principal: @bob, action: Ability::Action.system!(Workflow::CREATE_KEY))
    get halon_workflows_path, headers: inertia_headers
    assert_not inertia_props["canCreate"]
  end

  test "a member makes a draft from the library, asks an admin to publish it, and the admin publishes it from the request" do
    sign_in(users(:bob), @workspace)
    post halon_workflows_path, params: { template: "probing_scan", time_zone: "Europe/Belgrade" }
    workflow = @workspace.workflows.find_by!(name: "Look for probing in the logs")
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

  test "running by hand starts a run as the workflow and opens it" do
    workflow = published
    sign_in(users(:bob), @workspace)

    perform_enqueued_jobs { post run_workflow_path(workflow), params: { inputs: { query: "api" } } }
    run = workflow.runs.find_by!(test: false)
    assert_redirected_to workflow_path(workflow, run: run.id)
    assert_equal "Look around is running.", flash[:notice]
    assert_equal({ "query" => "api" }, run.inputs)
  end

  test "a run takes only the trigger's questions as plain answers, whatever else is sent" do
    workflow = published
    sign_in(users(:bob), @workspace)

    perform_enqueued_jobs { post run_workflow_path(workflow), params: { inputs: { query: { nested: "x" }, unasked: "y" } } }

    assert_equal({ "query" => "db" }, workflow.runs.sole.inputs)
  end

  test "a test run is never a workflow's last run, on the list, its page or for Halon, and stays on the Runs tab marked as a test" do
    workflow = published
    run = perform_enqueued_jobs { WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, test: true) }
    sign_in(users(:alice), @workspace)

    get halon_workflows_path, headers: inertia_headers
    assert_nil inertia_props["workflows"].find { |row| row["id"] == workflow.id }["lastRun"]
    tested = inertia_props["runs"].find { |row| row["id"] == run.id }
    assert tested["test"]

    get workflow_path(workflow), headers: inertia_headers
    assert_nil inertia_props["workflow"]["lastRun"]
    assert_nil Workflow::Listing.summary(workflow.reload)[:last_run]
    assert_nil Workflow::Listing.for(@workspace).find { |each| each[:name] == workflow.name }[:last_run]
  end

  test "making workflows is a member default an admin can take away from one member, who then cannot draft, test or have Halon make one" do
    workflow = published
    Ability::Grant.withhold!(workspace: @workspace, principal: @bob, action: Ability::Action.system!(Workflow::CREATE_KEY))
    sign_in(users(:bob), @workspace)

    assert_no_difference -> { @workspace.workflows.count } do
      post halon_workflows_path, params: { template: "probing_scan", time_zone: "Europe/Belgrade" }
    end
    assert_no_difference -> { workflow.runs.count } do
      post workflow_test_runs_path(workflow)
    end
    said = Conversation::Tools::CreateWorkflow.new(Conversation::Turn.new(Conversation.start_personal!(workspace: @workspace, member: @bob), asker: @bob))
                                              .call(template: "check_later", params: { resource: "web", in_minutes: 30, reply_in_chat: true })
    assert_equal "Bob Jones is not allowed to make workflows.", said
    assert_equal WorkspaceMembership::DEFAULT_NO_ACCESS, @bob.reload.default_access.find { |access| access.action&.key == Workflow::CREATE_KEY }.state

    Ability::Grant.find_by!(principal: @bob, action: Ability::Action.system!(Workflow::CREATE_KEY)).destroy!
    post halon_workflows_path, params: { template: "probing_scan", time_zone: "Europe/Belgrade" }
    assert_equal "Look for probing in the logs was made as a draft.", flash[:notice]
  end

  test "a run opens on the canvas with each step, and pinning and stopping it each say so" do
    workflow = published
    sign_in(users(:alice), @workspace)
    perform_enqueued_jobs { post run_workflow_path(workflow) }
    run = workflow.runs.sole

    get workflow_path(workflow, run: run.id), headers: inertia_headers
    assert_equal [ "look" ], inertia_props["run"]["steps"].map { |step| step["stepKey"] }

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
    suggestion = inertia_props["suggestions"].sole
    assert_equal "The search named no service.", suggestion["reason"]

    post workflow_suggestion_accept_path(workflow, edit.id)
    assert_match "was accepted.", flash[:notice]
    assert_equal({ "query" => "web" }, workflow.draft.steps.sole.dig("config", "arguments"))
  end

  test "the page says which revision of the draft it shows, and publishing an older one is refused" do
    workflow = drafted
    sign_in(users(:alice), @workspace)

    get workflow_path(workflow), headers: inertia_headers
    shown = inertia_props["workflow"]["draftRevision"]
    assert_equal workflow.draft.revision, shown
    workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { step_id: "look", changes: { config: { arguments: { query: "db" } } } }, by: @bob)

    post publish_workflow_path(workflow), params: { revision: shown }

    assert_equal "Someone changed the draft since you looked, so look again before publishing.", flash[:alert]
    refute workflow.reload.live?
  end

  test "a suggestion of several changes is added whole or not at all" do
    workflow = published
    first = workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { step_id: "look", changes: { config: { arguments: { query: "web" } } } },
                           by: nil, halon: true, reason: "The search named no service.")
    workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_CONFIG, payload: { step_id: "gone", changes: { config: { arguments: {} } } },
                   by: nil, halon: true, reason: "And the other step.", change_set_id: first.change_set_id)
    sign_in(users(:alice), @workspace)

    post workflow_suggestions_accept_path(workflow), params: { change_set_id: first.change_set_id }

    assert flash[:alert].present?
    assert_nil workflow.reload.draft
    assert_equal Workflow::Edit::STATUS_PROPOSED, first.reload.status
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
