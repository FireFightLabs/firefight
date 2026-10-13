require "test_helper"

class WorkflowTriggerServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_failure).returns({})
  end

  def look = { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => { "query" => "{{trigger.incident.identifier}}" } } }

  def published(name, trigger, steps: [ look ])
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "inputs" => [] }.merge(trigger), steps: steps, edges: [])
    assert_empty draft.problems
    result = WorkflowPublishService.new(workflow).publish!(draft.reload, by: @alice)
    assert result.ok, result.words
    workflow.reload
  end

  def condition(field, *values) = { "field" => field, "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => values }

  def domain_event(record) = DomainEvent.new(event_id: record.id, event_type: record.event_type, incident_id: record.incident_id, data: {}, occurred_at: Time.current)

  def heard(record)
    perform_enqueued_jobs { Workflows::EventSubscriber.handle(domain_event(record)) }
  end

  def created_event(incident = @incident) = incident.record_change!(IncidentEvent::INCIDENT_CREATED, by: @alice)

  test "a declared incident that matches the conditions starts a run with the incident as its trigger data" do
    critical = published("Critical", { "kind" => Workflow::Trigger::KIND_INCIDENT_DECLARED, "conditions" => [ condition("severity", "critical") ] })
    major = published("Major", { "kind" => Workflow::Trigger::KIND_INCIDENT_DECLARED, "conditions" => [ condition("severity", "major") ] })

    heard(created_event)

    run = critical.runs.sole
    assert_equal Workflow::Run::STATUS_SUCCEEDED, run.status, run.error
    assert_equal Workflow::Trigger::KIND_INCIDENT_DECLARED, run.trigger_kind
    assert_equal Workflow::Run::STARTED_BY_TRIGGER, run.started_by_kind
    assert_equal "INC-001", run.trigger_payload.dig("incident", "identifier")
    assert_equal "INC-001", run.steps.find_by!(step_key: "look").input.dig("arguments", "query")
    assert_empty major.runs
  end

  test "one event starts a workflow once however often it is heard" do
    workflow = published("Declared", { "kind" => Workflow::Trigger::KIND_INCIDENT_DECLARED })
    event = created_event

    heard(event)
    heard(event)

    assert_equal 1, workflow.runs.count
  end

  test "an incident change starts only the workflows that chose it" do
    resolved = published("On resolve", { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "changes" => [ Workflow::Trigger::Changes::RESOLVED ] })
    status = published("On status", { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "changes" => [ Workflow::Trigger::Changes::STATUS ] })
    severity = published("On severity", { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "changes" => [ Workflow::Trigger::Changes::SEVERITY ] })
    event = @incident.record_change!(IncidentEvent::INCIDENT_RESOLVED, by: @alice) { @incident.update!(incident_status: incident_statuses(:resolved_ws1)) }

    heard(event)

    assert_equal 1, resolved.runs.count
    assert_equal 1, status.runs.count
    assert_empty severity.runs
    assert_equal [ Workflow::Trigger::Changes::RESOLVED, Workflow::Trigger::Changes::STATUS ], resolved.runs.sole.trigger_payload["change"]
  end

  test "a severity change hands on the value before and after" do
    workflow = published("On severity", { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "changes" => [ Workflow::Trigger::Changes::SEVERITY ],
                                          "conditions" => [ condition("severity", "major") ] })
    created_event
    event = @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: @alice) { @incident.update!(incident_severity: incident_severities(:major_ws1)) }

    heard(event)

    payload = workflow.runs.sole.trigger_payload
    assert_equal "Major", payload.dig("incident", "severity", "name")
    assert_equal({ "before" => "Critical", "after" => "Major" }, payload.dig("changes", "severity"))
    assert_equal [ Workflow::Trigger::Changes::SEVERITY ], payload["change"]
  end

  test "a follow up created starts a workflow listening for follow ups" do
    workflow = published("Follow ups", { "kind" => Workflow::Trigger::KIND_FOLLOW_UP_CHANGED, "changes" => [ Workflow::Trigger::Changes::FOLLOW_UP_CREATED ] })
    action = @incident.incident_actions.create!(description: "Add a pool size alarm", created_by: @alice)
    event = action.record_change!(IncidentEvent::ACTION_CREATED, by: @alice)

    heard(event)

    assert_equal "Add a pool size alarm", workflow.runs.sole.trigger_payload.dig("action", "description")
  end

  test "a change a workflow made never starts that same workflow again" do
    workflow = published("On severity", { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "changes" => [ Workflow::Trigger::Changes::SEVERITY ] })
    other = published("Also on severity", { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "changes" => [ Workflow::Trigger::Changes::SEVERITY ] })
    event = @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: workflow.agent) { @incident.update!(incident_severity: incident_severities(:major_ws1)) }

    heard(event)

    assert_empty workflow.runs
    assert_equal 1, other.runs.count
  end

  test "the workspace's ceiling of event runs an hour is kept, and a refused start is kept on the workflow" do
    @workspace.update!(workflow_event_runs_per_hour: 1)
    workflow = published("Declared", { "kind" => Workflow::Trigger::KIND_INCIDENT_DECLARED })

    heard(created_event)
    heard(created_event(incidents(:active_major_ws1)))

    assert_equal 1, workflow.runs.count
    assert_match "as many as it allows", workflow.reload.trigger_refusal
  end

  test "nothing is heard without the workflows flag" do
    workflow = published("Declared", { "kind" => Workflow::Trigger::KIND_INCIDENT_DECLARED })
    FeatureFlags.disable!(@workspace, FeatureFlags::WORKFLOWS)

    assert_no_enqueued_jobs(only: WorkflowEventJob) { Workflows::EventSubscriber.handle(domain_event(created_event)) }
    assert_empty workflow.runs
  end

  test "an alert starts a run once per group, so a storm starts one" do
    stub_successful_slack_workflow
    stub_post_message
    stub_update_message
    workflow = published("Alerts", { "kind" => Workflow::Trigger::KIND_ALERT_RECEIVED, "conditions" => [ condition("service", "checkout") ] },
                         steps: [ look.merge("config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => { "query" => "{{trigger.alert.title}}" } }) ])
    source = AlertSource.create!(workspace: @workspace, name: "Monitoring", provider: AlertSource::PROVIDER_GENERIC)
    policy = @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
    policy.policy_rules.create!(priority: 1, conditions: [], outcome: { "action" => AlertIngestService::ACTION_AUTO_CREATE })
    service = AlertIngestService.new(source)

    service.ingest({ "title" => "Checkout 504s", "service" => "checkout", "status" => Alert::STATUS_FIRING, "fingerprint" => "a" }, {})
    service.ingest({ "title" => "Checkout 502s", "service" => "checkout", "status" => Alert::STATUS_FIRING, "fingerprint" => "b" }, {})
    service.ingest({ "title" => "Search slow", "service" => "search", "status" => Alert::STATUS_FIRING, "fingerprint" => "c" }, {})
    perform_enqueued_jobs(only: WorkflowEventJob)


    run = workflow.runs.sole
    assert_equal "Checkout 504s", run.trigger_payload.dig("alert", "title")
    assert_equal AlertIngestService::ACTION_AUTO_CREATE, run.trigger_payload["outcome"]
    assert run.trigger_payload.dig("incident", "identifier").present?
  end

  test "a notice starts a run when it is raised and again only when it gets worse" do
    workflow = published("Notices", { "kind" => Workflow::Trigger::KIND_NOTICE_RAISED, "conditions" => [ condition("signal", Investigation::Notice::SIGNAL_DISK) ] })
    reading = ->(severity) { Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: "db disk", summary: "Filling up", severity: severity) }

    perform_enqueued_jobs do
      Investigation::Notice.observe!(@workspace, reading.call(Investigation::Notice::SEVERITY_LOW))
      Investigation::Notice.observe!(@workspace, reading.call(Investigation::Notice::SEVERITY_LOW))
      Investigation::Notice.observe!(@workspace, reading.call(Investigation::Notice::SEVERITY_HIGH))
    end

    changes = workflow.runs.order(:created_at).map { |run| run.trigger_payload["change"] }
    assert_equal [ Investigation::Notice::CHANGE_RAISED, Investigation::Notice::CHANGE_WORSENED ], changes
  end

  test "an investigation that concluded starts a run, and one a person stopped does not" do
    workflow = published("Findings", { "kind" => Workflow::Trigger::KIND_INVESTIGATION_FINISHED })
    concluded = Investigation.create!(workspace: @workspace, subject: @incident, trigger_source: Investigation::TRIGGER_DASHBOARD, max_spend_cents: 100, max_turns: 5)
    perform_enqueued_jobs { concluded.finish!(status: Investigation::STATUS_SUCCEEDED) }
    stopped = Investigation.create!(workspace: @workspace, subject: @incident, trigger_source: Investigation::TRIGGER_DASHBOARD, max_spend_cents: 100, max_turns: 5)
    perform_enqueued_jobs { stopped.finish!(status: Investigation::STATUS_CANCELED) }


    run = workflow.runs.sole
    assert_equal concluded.id, run.trigger_payload.dig("investigation", "id")
    assert_equal "INC-001", run.trigger_payload.dig("incident", "identifier")
  end

  test "a failed run starts the workflows listening for failures, never its own" do
    failing = published("Breaks", { "kind" => Workflow::Trigger::KIND_RUN_FAILED },
                        steps: [ { "id" => "nope", "name" => "nope", "kind" => "call_tool", "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS } } ])
    watcher = published("Watcher", { "kind" => Workflow::Trigger::KIND_RUN_FAILED, "conditions" => [ condition("workflow", failing.slug) ] })
    failing.agent.ability_grants.destroy_all

    perform_enqueued_jobs { WorkflowRunService.new(failing).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }

    assert_equal Workflow::Run::STATUS_FAILED, failing.runs.sole.status
    run = watcher.runs.sole
    assert_equal "Breaks", run.trigger_payload.dig("run", "workflow")
    assert_equal "nope", run.trigger_payload.dig("run", "failed_step")
  end

  test "telling workflows that broke never stops what happened from finishing" do
    failing = published("Breaks", { "kind" => Workflow::Trigger::KIND_MANUAL })
    Workflow::Trigger::Events.stubs(:listened?).raises(ActiveRecord::ConnectionTimeoutError, "no connection")

    assert_nothing_raised { EventRouter.route(domain_event(created_event)) }

    investigation = Investigation.create!(workspace: @workspace, subject: @incident, trigger_source: Investigation::TRIGGER_DASHBOARD, max_spend_cents: 100, max_turns: 5)
    assert investigation.finish!(status: Investigation::STATUS_SUCCEEDED)

    reading = Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: "db disk", summary: "Filling up", severity: Investigation::Notice::SEVERITY_LOW)
    assert Investigation::Notice.observe!(@workspace, reading)

    run = failing.runs.create!(workspace: @workspace, version: failing.live_version, status: Workflow::Run::STATUS_FAILED, trigger_kind: Workflow::Trigger::KIND_MANUAL,
                               start_key: "broke", started_by_kind: Workflow::Run::STARTED_BY_PERSON, error: "It broke.")
    WorkspaceAdapter.for(@workspace).class.any_instance.expects(:post_workflow_failure).once.returns({})
    WorkflowRunEndService.new(run).ended!
  end

  test "a trigger's conditions and choices are checked before publishing" do
    workflow = Workflow.create!(workspace: @workspace, name: "Wrong", created_by: @alice)
    draft = workflow.open_draft!(by: @alice)
    draft.update!(trigger: { "kind" => Workflow::Trigger::KIND_INCIDENT_CHANGED, "inputs" => [], "changes" => [ "colour" ],
                             "conditions" => [ { "field" => "severity", "operator" => "is_loud" } ] }, steps: [ look ])

    problems = draft.problems

    assert_includes problems, "The trigger's condition 1 has an unknown operator."
    assert_includes problems, "What changes it cannot be colour, only #{Workflow::Trigger::Changes::INCIDENT.join(', ')}."
  end

  test "only a trigger something happening starts may hold conditions" do
    problems = Workflow::Trigger.problems({ "kind" => Workflow::Trigger::KIND_MANUAL, "inputs" => [], "conditions" => [ condition("severity", "major") ] })

    assert_includes problems, "Only a trigger that something happening starts can have conditions."
  end
end
