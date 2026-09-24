require "test_helper"

class InvestigationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "a run on an incident opens over the incident" do
    investigation = investigation_run

    get investigation_url(investigation)

    assert_redirected_to incident_path(@incident, Investigation::QUERY_PARAM => investigation.id)
  end

  test "the incident page draws the run the address asks for, whole" do
    investigation = investigation_run
    invocation = Ability::Invocation.create!(
      workspace: @workspace, principal: SystemAgent.investigator, action_key: "github.fetch_file",
      decision: Ability::Invocation::DECISION_ALLOW, source: AbilityGateway::SOURCE_INVESTIGATION,
      principal_label: SystemAgent.investigator.principal_label, idempotency_key: SecureRandom.uuid
    )
    step = investigation.steps.create!(position: 1, tool_name: "github_fetch_file", label: "Github fetch file billing_controller.rb",
                                       action_key: "github.fetch_file", status: Investigation::Step::STATUS_RUNNING, invocation: invocation)
    step.succeed!(compacted_result: "before_action :require_admin!")
    investigation.record_hypothesis!(assertion: "A missing method", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1 ])
    investigation.conclude!(summary: "require_admin! is defined nowhere", hypothesis_assertion: "A missing method",
                            evidence: [ { claim: "The controller calls it", steps: [ 1 ] } ])

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers

    shown = inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]
    assert_equal "A missing method", shown.dig("finding", "cause")
    assert_equal [ 1 ], shown.dig("finding", "evidence", 0, "steps")
    assert_equal 1, shown.dig("hypotheses", 0, "settledAfterStep")
    assert_equal "before_action :require_admin!", shown.dig("steps", 0, "result")
    assert_equal Ability::Invocation::DECISION_ALLOW, shown.dig("steps", 0, "receipt", "decision")
  end

  test "a technical cause is never shown, only the plain sentence the thread was told" do
    investigation = investigation_run(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")

    get incident_url(@incident, Investigation::QUERY_PARAM => investigation.id), headers: inertia_headers

    assert_equal Investigation::GAVE_UP, inertia_props.dig(IncidentsController::PROP_OPEN_INVESTIGATION, "stoppedBecause")
  end

  test "a run on another incident opens nothing" do
    other = investigation_run(subject: incidents(:active_major_ws1))

    get incident_url(@incident, Investigation::QUERY_PARAM => other.id), headers: inertia_headers

    assert_nil inertia_props[IncidentsController::PROP_OPEN_INVESTIGATION]
  end

  test "a rehearsal cannot be opened" do
    rehearsal = investigation_run(rehearsal: true, trigger_source: Investigation::TRIGGER_REHEARSAL)

    get investigation_url(rehearsal), headers: inertia_headers

    assert_response :not_found
  end

  private

  def investigation_run(**attributes)
    @workspace.investigations.create!(
      { subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
        max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED }.merge(attributes)
    )
  end
end
