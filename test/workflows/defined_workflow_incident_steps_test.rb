require "test_helper"

class DefinedWorkflowIncidentStepsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_failure).returns({})
    stub_successful_slack_workflow
  end

  def step(id, kind, config = {}) = { "id" => id, "name" => id, "kind" => kind, "config" => config }

  def edge(from, to, route = nil) = { "from" => from, "to" => to, "route" => route }.compact

  # The read a change ends with.
  def check = step("check", "call_tool", { "tool" => FirefightTools::GET_INCIDENT, "arguments" => { "incident" => "INC-001" } })

  def published(name, steps:, edges: [])
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => "manual", "inputs" => [] }, steps: steps, edges: edges)
    assert_empty draft.problems
    result = WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice)
    assert result.ok, result.words
    workflow.reload
  end

  def changed_then_checked(name, change)
    published(name, steps: [ change, check ], edges: [ edge(change["id"], "check") ])
  end

  # Search indexing calls a model, which the tests never reach.
  QUIET = [ WriteSearchEmbeddingJob, SearchDocumentIndexJob, InvestigationJob ].freeze

  def start(workflow, except: QUIET, **options)
    run = nil
    perform_enqueued_jobs(except: except) do
      run = WorkflowRunService.new(workflow).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice, **options)
    end
    run.reload
  end

  def output(run, key) = run.steps.find_by!(step_key: key).output

  test "open incident declares one through the declare form and hands on its identifier" do
    workflow = changed_then_checked("Declare", step("open", "open_incident", { "name" => "Checkout down", "severity" => "critical", "undo" => "Cancel it." }))

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    identifier = output(run, "open")["incident"]
    incident = @workspace.incidents.find_by!(identifier: identifier)
    assert_equal "Checkout down", incident.name
    assert_equal workflow.agent, incident.declared_by
  end

  test "update incident changes one thing, as the workflow's own identity, and a test run only says what it would do" do
    change = step("bump", "update_incident", { "incident" => "INC-001", "change" => "severity", "severity" => "major", "undo" => "Set it back to critical." })
    workflow = changed_then_checked("Bump", change)

    tried = start(workflow, test: true)
    assert_equal true, output(tried, "bump")["simulated"]
    assert_equal "critical", @incident.reload.incident_severity.slug

    run = start(workflow)
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal "major", @incident.reload.incident_severity.slug
    assert_equal workflow.agent, @incident.incident_events.order(:created_at).last.actor
  end

  test "update incident makes someone lead, and says what each change needs before it is published" do
    workflow = changed_then_checked("Lead", step("lead", "update_incident", { "incident" => "INC-001", "change" => "lead", "member" => "bob@example.com", "undo" => "Make Alice lead again." }))

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal workspace_memberships(:bob_workspace_one), @incident.reload.lead
    problems = DefinedWorkflow::Steps::UpdateIncident.problems(step("x", "update_incident", { "incident" => "INC-001", "change" => "role" }), @workspace)
    assert_includes problems, "x needs who it makes take the role."
    assert_includes problems, "x needs the role it fills."
  end

  test "post incident update posts again while the incident is live, and stops once it is resolved" do
    workflow = published("Keep telling", steps: [ step("tell", "post_incident_update", { "incident" => "INC-001", "message" => "Still on it.", "every_minutes" => 30 }) ])

    run = start(workflow)
    assert_equal Workflow::Run::STATUS_WAITING, run.status, run.error
    updates = -> { @incident.incident_updates.where.not(message: nil).count }
    assert_equal 1, updates.call

    travel 31.minutes do
      perform_enqueued_jobs(except: QUIET) { SolidWorkflow::SweeperJob.perform_now }
    end
    assert_equal 2, updates.call

    IncidentLifecycleService.new(@workspace).change_status(@incident, { incident_status: incident_statuses(:resolved_ws1) }, changed_by: @alice)
    travel 62.minutes do
      perform_enqueued_jobs(except: QUIET) { SolidWorkflow::SweeperJob.perform_now }
    end
    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal 2, output(run, "tell")["posted"]
  end

  test "page on call escalates to a member when no on-call tool is connected" do
    workflow = published("Wake", steps: [ step("wake", "page_on_call", { "incident" => "INC-001", "reason" => "Checkout is down.", "escalate_to" => "bob@example.com" }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal [], output(run, "wake")["on_call"]
    assert_includes @incident.reload.on_call_members, workspace_memberships(:bob_workspace_one)
  end

  test "create follow up adds one to the incident and hands on its id" do
    workflow = changed_then_checked("Follow up", step("later", "create_follow_up", { "incident" => "INC-001", "description" => "Raise the pool size", "undo" => "Delete it." }))

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    action = @incident.incident_actions.find(output(run, "later")["follow_up"])
    assert_equal [ "Raise the pool size", IncidentAction::ACTION_TYPE_FOLLOWUP ], [ action.description, action.action_type ]
  end

  test "message a person reaches the incident's lead in their direct messages" do
    @incident.lead = workspace_memberships(:bob_workspace_one)
    WorkspaceAdapter.for(@workspace).class.any_instance.expects(:post_channel_message)
                    .with(has_entries(channel_id: workspace_memberships(:bob_workspace_one).platform_user_id, message: "You are needed on INC-001."))
                    .returns({ channel_id: "D1", message_id: "1.1" })
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:get_message_permalink).returns({ permalink: nil })
    workflow = published("Tell lead", steps: [ step("tell", "message_person", { "to" => "lead", "incident" => "INC-001", "message" => "You are needed on INC-001." }) ])

    run = start(workflow)

    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal [ "Bob Jones" ], output(run, "tell")["told"]
  end

  test "status page update only calls a tool of a connected status page that changes something" do
    problems = DefinedWorkflow::Steps::StatusPageUpdate.problems(step("page", "status_page_update", { "tool" => FirefightTools::SEARCH_INCIDENTS, "undo" => "x" }), @workspace)

    assert_includes problems, "page calls search_incidents, which is not a tool of a connected status page that changes something."
  end

  test "status page update calls the tools of a connected Statuspage or Instatus that change a page, and never their reads" do
    [ Integrations::Providers::Statuspage.key, Integrations::Providers::Instatus.key ].each do |provider|
      integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: provider, name: provider.titleize)
      Integrations::DiscoveryService.sync!(integration)
      update = integration.tools.find_by!(name: "post_incident_update")
      read = integration.tools.find_by!(name: "list_incidents")
      workspace = Workspace.find(@workspace.id)

      assert DefinedWorkflow::Steps::StatusPageUpdate.status_page_tool?(workspace, update.model_facing_name), "#{provider} posts an update"
      assert_not DefinedWorkflow::Steps::StatusPageUpdate.status_page_tool?(workspace, read.model_facing_name), "#{provider} only reads its incidents"
    end
  end

  test "investigate starts one and waits for what it finds" do
    workflow = published("Look into it", steps: [ step("look", "investigate", { "incident" => "INC-001" }) ])
    Investigation.stubs(:start_refusal).returns(nil)

    run = start(workflow)
    assert_equal Workflow::Run::STATUS_WAITING, run.status, run.error
    investigation = @incident.investigations.find_by!(trigger_source: Investigation::TRIGGER_WORKFLOW)
    assert_equal workflow.agent, investigation.triggered_by

    perform_enqueued_jobs(except: QUIET) { investigation.finish!(status: Investigation::STATUS_SUCCEEDED) }

    run.reload
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal [ "succeeded", investigation.id ], output(run, "look").values_at("status", "investigation_id")
  end

  test "classify takes the route Halon names, and the otherwise route for one it does not" do
    Investigation.stubs(:unavailable_reason).returns(nil)
    sort = step("sort", "classify", { "data" => "disk at 98%", "routes" => %w[noise outage] })
    workflow = published("Sort", steps: [ sort ])

    FirefightAi::WorkflowAnswer.any_instance.stubs(:answer).returns(FirefightAi::WorkflowAnswer::Answer.new(verdict: "problem", summary: "Real.", fields: { "route" => "outage" }))
    assert_equal "outage", start(workflow).steps.find_by!(step_key: "sort").route

    FirefightAi::WorkflowAnswer.any_instance.stubs(:answer).returns(FirefightAi::WorkflowAnswer::Answer.new(verdict: "unsure", summary: "?", fields: { "route" => "cheese" }))
    assert_equal "other", start(workflow).steps.find_by!(step_key: "sort").route
  end
end
