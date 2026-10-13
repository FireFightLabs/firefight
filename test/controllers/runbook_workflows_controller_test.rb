require "test_helper"

# The dashboard's side of a runbook that links a workflow: linking and unlinking it in the editor, Run it on the runbook
# and in an incident, and everything about it only where the workspace has workflows.
class RunbookWorkflowsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    sign_in(users(:alice), @workspace)
    @runbook = @workspace.runbooks.create!(name: "Release Firefight", inputs: [ { key: "bump", question: "Which version bump?", default: "patch" } ])
    @runbook.sync_steps!([ { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "{{bump}}" } } ])
  end

  test "without workflows Run it answers not found, the editor offers no workflows and the page ships none" do
    post runbook_runs_url(@runbook), params: { inputs: { bump: "minor" } }
    assert_response :not_found

    get settings_runbooks_url, headers: inertia_partial_headers("settings/runbooks", SettingsController::RUNBOOK_WORKFLOWS)
    assert_equal [], inertia_props[SettingsController::RUNBOOK_WORKFLOWS]

    get settings_runbooks_url, headers: inertia_headers
    assert_nil inertia_props["runbooks"].find { |runbook| runbook["id"] == @runbook.id }["workflow"]
  end

  test "the page ships the workflow a runbook links with its questions, and the editor the workflows it can link" do
    workflow = published_workflow

    get settings_runbooks_url, headers: inertia_headers
    shown = inertia_props["runbooks"].find { |runbook| runbook["id"] == @runbook.id }["workflow"]
    assert_equal({ "id" => workflow.id, "name" => "Release Firefight", "state" => Workflow::STATE_LIVE,
                   "inputs" => [ { "key" => "bump", "question" => "Which version bump?", "default" => "patch" } ], "runBlockedReason" => nil }, shown)

    get settings_runbooks_url, headers: inertia_partial_headers("settings/runbooks", SettingsController::RUNBOOK_WORKFLOWS)
    assert_includes inertia_props[SettingsController::RUNBOOK_WORKFLOWS], { "id" => workflow.id, "name" => "Release Firefight", "state" => Workflow::STATE_LIVE }
  end

  test "Run it starts the linked workflow with the answers given, says so and links its run" do
    workflow = published_workflow

    post runbook_runs_url(@runbook), params: { inputs: { bump: "minor", other: "ignored" } }, headers: { "HTTP_REFERER" => settings_runbooks_url }

    run = workflow.runs.sole
    assert_redirected_to settings_runbooks_url
    assert_equal "Release Firefight is running.", flash[:notice]
    assert_equal [ { "label" => "Follow its run", "url" => workflow_run_path(workflow, run) } ], flash.inertia[:links].map(&:stringify_keys)
    assert_equal({ "bump" => "minor" }, run.inputs)
    assert_equal [ workflow.agent, @admin ], [ run.agent, run.started_by ]
  end

  test "Run it in an incident names the incident on the run" do
    workflow = published_workflow
    incident = incidents(:active_critical_ws1)

    post runbook_runs_url(@runbook), params: { incident_id: incident.id, inputs: { bump: "minor" } }, headers: { "HTTP_REFERER" => incident_url(incident) }

    assert_redirected_to incident_url(incident)
    assert_equal incident.identifier, workflow.runs.sole.trigger_payload.dig("incident", "identifier")
  end

  test "Run it on a workflow nobody published yet says why and starts nothing" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)

    post runbook_runs_url(@runbook), params: { inputs: { bump: "minor" } }, headers: { "HTTP_REFERER" => settings_runbooks_url }

    assert_equal "Release Firefight has no published version to run.", flash[:alert]
    assert_empty @runbook.reload.workflow.runs
  end

  test "the editor links a workflow and unlinks it, each said in a toast" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    other = Workflow.create!(workspace: @workspace, name: "Rollback")

    patch runbook_url(@runbook), params: { name: "Release Firefight", workflow_id: other.id }
    assert_equal other, @runbook.reload.workflow
    assert_equal "Release Firefight was updated.", flash[:notice]

    patch runbook_url(@runbook), params: { name: "Release Firefight", workflow_id: "" }
    assert_nil @runbook.reload.workflow
    assert_equal "Release Firefight was updated.", flash[:notice]
  end

  test "a workflow from another workspace cannot be linked" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    elsewhere = Workflow.create!(workspace: workspaces(:slack_workspace_two), name: "Elsewhere")

    patch runbook_url(@runbook), params: { name: "Release Firefight", workflow_id: elsewhere.id }

    assert_response :not_found
    assert_not_equal elsewhere, @runbook.reload.workflow
  end

  test "with workflows on, a form still sending steps that run is told they belong to the workflow, and nothing changes" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)

    patch runbook_url(@runbook), params: { name: "Renamed", steps: [ { title: "Restart", tool: "restart" } ] }, headers: { "HTTP_REFERER" => settings_runbooks_url }

    assert_equal "Release Firefight", @runbook.reload.name
    assert_equal RunbooksController::RUNS_IN_ITS_WORKFLOW, session["inertia_errors"][:base]
    assert @runbook.runbook_steps.none?(&:tool?)
  end

  test "an incident's runbooks ship the workflow each runs, with why the person cannot run it" do
    workflow = published_workflow
    incident = incidents(:active_critical_ws1)
    incident.incident_runbooks.create!(runbook: @runbook, workspace: @workspace)
    workflow.update!(enabled: false)

    get incident_url(incident), headers: inertia_headers

    shown = inertia_props["incident"]["runbooks"].sole["workflow"]
    assert_equal [ workflow.id, "Release Firefight is switched off." ], shown.values_at("id", "runBlockedReason")
  end

  private

  def published_workflow
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = @runbook.reload.workflow
    assert WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @admin).ok
    workflow.reload
  end
end
