require "test_helper"

class IncidentUpdateWorkflowTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities, :incident_lifecycle_stages, :incident_statuses

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(incidents_channel_id: "C_INCIDENTS")
    @member = workspace_memberships(:alice_workspace_one)
    @severity = incident_severities(:critical_ws1)
    @status = incident_statuses(:investigating_ws1)

    @incident = Incident.create!(
      workspace: @workspace,
      declared_by: @member,
      incident_status: @status,
      incident_severity: @severity,
      name: "Test incident",
      is_private: false,
      channel_id: "C_INCIDENT",
      initial_message_ts: "1234567890.111111",
      announcement_message_ts: "1234567890.222222",
      source: Incident::SOURCE_SLACK
    )
  end

  test "full workflow succeeds" do
    stub_all_side_effects

    workflow = IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
    assert_equal 6, workflow.steps.count
    assert workflow.steps.all?(&:succeeded?)
  end

  test "skips quick actions update when no initial_message_ts" do
    @incident.update!(initial_message_ts: nil)
    stub_all_side_effects

    workflow = IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
  end

  test "skips announcement thread when no announcement_message_ts" do
    @incident.update!(announcement_message_ts: nil)
    stub_all_side_effects

    workflow = IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal "succeeded", workflow.state
  end

  test "posts update message to incident channel" do
    stub_all_side_effects

    Slack::Client.expects(:post_message).at_least_once.returns({ ok: true, ts: "123.456" })

    IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)
  end

  test "passes previous values through workflow context" do
    stub_all_side_effects

    workflow = IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context(
      previous_status_name: "Investigating",
      previous_severity_name: "Critical"
    ))

    assert_equal "Investigating", workflow.context["previous_status_name"]
    assert_equal "Critical", workflow.context["previous_severity_name"]
  end

  test "attaches a matching runbook on update" do
    stub_all_side_effects
    runbook = matching_runbook

    IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)

    assert_includes @incident.incident_runbooks.reload.map(&:runbook), runbook
  end

  test "does not attach a non-matching runbook on update" do
    stub_all_side_effects
    runbook = @workspace.runbooks.create!(name: "Only for majors")
    runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ incident_severities(:major_ws1).id ]
    )

    IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)

    assert_not_includes @incident.incident_runbooks.reload.map(&:runbook), runbook
  end

  test "does not duplicate an already-attached runbook on update" do
    stub_all_side_effects
    runbook = matching_runbook
    RunbookAttachmentService.new(@workspace).attach(incident: @incident, runbook: runbook)

    IncidentUpdateWorkflow.start_inline!(@incident, context: workflow_context)

    assert_equal 1, @incident.incident_runbooks.where(runbook: runbook).count
  end

  private

  def matching_runbook
    runbook = @workspace.runbooks.create!(name: "Critical response")
    runbook.incident_conditions.create!(
      workspace: @workspace,
      condition_field: IncidentCondition::FIELD_SEVERITY,
      operator: IncidentCondition::OPERATOR_ONE_OF,
      values: [ @severity.id ]
    )
    runbook
  end

  def workflow_context(previous_status_name: nil, previous_severity_name: nil)
    {
      updated_by_platform_user_id: @member.platform_user_id,
      message: "Working on fix",
      previous_status_name: previous_status_name,
      previous_severity_name: previous_severity_name
    }
  end

  def stub_all_side_effects
    stub_update_message
    stub_post_message
    stub_set_channel_topic
    stub_set_channel_purpose
  end
end
