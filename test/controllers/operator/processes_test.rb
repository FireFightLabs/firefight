require "test_helper"

class Operator::ProcessesTest < ActionDispatch::IntegrationTest
  setup do
    @operator = users(:alice)
    @previous = ENV[OperatorCredential::OPERATOR_IDS_ENV]
    ENV[OperatorCredential::OPERATOR_IDS_ENV] = @operator.id
    @incident = incidents(:active_critical_ws1)
    @workflow = SolidWorkflow::Workflow.create!(
      name: "incident.creation.v1", workflow_class: "IncidentCreationWorkflow", subject: @incident, state: "failed"
    )
    @step = @workflow.steps.create!(name: "invite_responders", position: 0, status: "failed", attempts: 3, max_attempts: 3,
                                    last_error: "AdapterError::NotInChannel")
  end

  teardown do
    ENV[OperatorCredential::OPERATOR_IDS_ENV] = @previous
  end

  test "nobody but a verified operator reaches the processes or acts on them" do
    sign_in(users(:bob), workspaces(:slack_workspace_one))

    get operator_incidents_path
    assert_response :not_found
    post run_again_operator_workflow_step_path(@step)
    assert_response :not_found
    assert @step.reload.failed?
  end

  test "incidents are listed across workspaces, and one opens its whole process" do
    as_operator

    get operator_incidents_path, headers: inertia_headers
    assert inertia_props["incidents"].any? { |row| row["id"] == @incident.id }

    get operator_incident_path(@incident), headers: inertia_headers
    step = inertia_props["entries"].find { |entry| entry["key"] == "step-#{@step.id}" }
    assert_equal @step.id, step["retryStepId"]
  end

  test "workflows filter by state and kind, and one opens with its steps placed and its events" do
    as_operator

    get operator_workflows_path(state: "failed", kind: "IncidentCreationWorkflow"), headers: inertia_headers
    assert_equal [ @workflow.id ], inertia_props["workflows"].map { |row| row["id"] } & [ @workflow.id ]
    assert inertia_props["workflows"].all? { |row| row["state"] == "failed" }

    get operator_workflow_path(@workflow), headers: inertia_headers
    assert_equal [ 0, 0 ], inertia_props.dig("workflow", "steps", 0).values_at("column", "row")
  end

  test "a failed step runs again, and the workflow is running again, which the toast says" do
    as_operator
    SolidWorkflow::Workflow.any_instance.stubs(:enqueue_next_steps)

    post run_again_operator_workflow_step_path(@step), headers: { "HTTP_REFERER" => operator_workflow_url(@workflow) }

    assert_redirected_to operator_workflow_url(@workflow)
    assert_equal "invite_responders will run again now.", flash[:notice]
    assert @step.reload.pending?
    assert @workflow.reload.running?
  end

  test "a failed step can be skipped, and a step that did not fail cannot be run again" do
    as_operator
    SolidWorkflow::Workflow.any_instance.stubs(:enqueue_next_steps)

    post skip_operator_workflow_step_path(@step)
    assert @step.reload.skipped?

    post run_again_operator_workflow_step_path(@step)
    assert_equal "Only a failed step can be run again.", flash[:alert]
  end

  test "a running workflow pauses, resumes and cancels, each under the operator's name" do
    as_operator
    @workflow.update!(state: "running")
    SolidWorkflow::Workflow.any_instance.stubs(:enqueue_next_steps)

    post pause_operator_workflow_path(@workflow)
    assert @workflow.reload.paused?
    assert_equal "#{@operator.email} (operator)", @workflow.paused_by

    post resume_operator_workflow_path(@workflow)
    assert @workflow.reload.running?

    post cancel_operator_workflow_path(@workflow)
    assert @workflow.reload.cancelled?

    post pause_operator_workflow_path(@workflow)
    assert_equal "Only a running workflow can be paused.", flash[:alert]
  end

  test "a failed webhook delivery is sent again as a delivery of its own" do
    as_operator
    event = @incident.incident_events.create!(event_type: IncidentEvent::MILESTONE_NOTED, metadata: { statement: "x" })
    webhook = @incident.workspace.webhooks.create!(name: "Acme", url: "https://hooks.acme.dev/in", subscribed_events: [ IncidentEvent::INCIDENT_CREATED ])
    delivery = WebhookDelivery.create!(webhook: webhook, incident_event: event, event_type: IncidentEvent::INCIDENT_CREATED, signed_payload: "{}", state: :failed)

    assert_difference -> { WebhookDelivery.where(webhook: webhook).count }, 1 do
      post redeliver_operator_webhook_delivery_path(delivery)
    end
    assert_equal "Sending incident.created to Acme again.", flash[:notice]
  end

  private

  def as_operator
    sign_in(@operator, workspaces(:slack_workspace_one))
    Operator::BaseController.any_instance.stubs(:operator_verified?).returns(true)
  end
end
