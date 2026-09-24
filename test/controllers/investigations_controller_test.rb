require "test_helper"

class InvestigationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "the list shows the runs people see, newest first, with the answer or why there is none" do
    stopped = investigation_run(status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT, created_at: 1.hour.ago)
    answered = investigation_run
    answered.conclude!(summary: "The 14:02 deploy raised the pool size")
    investigation_run(rehearsal: true, trigger_source: Investigation::TRIGGER_REHEARSAL)

    get investigations_url, headers: inertia_headers

    listed = inertia_props[InvestigationsController::PROP_INVESTIGATIONS]
    assert_equal [ answered.id, stopped.id ], listed.map { |row| row["id"] }
    assert_equal [ "The 14:02 deploy raised the pool size", Investigation::BUDGET_SPENT ], listed.map { |row| row["answer"] }
    assert_equal @incident.identifier, listed.first["incidentIdentifier"]
    assert_equal 2, inertia_props.dig(InvestigationsController::PROP_PAGINATION, "totalCount")
  end

  test "one incident's runs, when its header has several" do
    mine = investigation_run
    investigation_run(subject: incidents(:active_major_ws1))

    get investigations_url(incident_id: @incident.id), headers: inertia_headers

    assert_equal [ mine.id ], inertia_props[InvestigationsController::PROP_INVESTIGATIONS].map { |row| row["id"] }
    assert_equal @incident.identifier, inertia_props.dig(InvestigationsController::PROP_INCIDENT, "identifier")
  end

  test "a technical cause is never shown, only the plain sentence the thread was told" do
    investigation_run(status: Investigation::STATUS_FAILED, error_summary: "Faraday::TimeoutError")

    get investigations_url, headers: inertia_headers

    assert_equal Investigation::GAVE_UP, inertia_props[InvestigationsController::PROP_INVESTIGATIONS].sole["answer"]
  end

  test "one run arrives whole: the finding with the steps each claim rests on, the theories and every step with its receipt" do
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

    get investigation_url(investigation), headers: inertia_headers

    shown = inertia_props[InvestigationsController::PROP_INVESTIGATION]
    assert_equal "A missing method", shown.dig("finding", "cause")
    assert_equal [ 1 ], shown.dig("finding", "evidence", 0, "steps")
    assert_equal [ 1 ], shown.dig("hypotheses", 0, "steps")
    assert_equal "before_action :require_admin!", shown.dig("steps", 0, "result")
    assert_equal Ability::Invocation::DECISION_ALLOW, shown.dig("steps", 0, "receipt", "decision")
  end

  test "a rehearsal cannot be opened" do
    rehearsal = investigation_run(rehearsal: true, trigger_source: Investigation::TRIGGER_REHEARSAL)

    get investigation_url(rehearsal), headers: inertia_headers

    assert_response :not_found
  end

  test "without Halon the page says why and goes back to the dashboard" do
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    get investigations_url

    assert_redirected_to dashboard_path
  end

  private

  def investigation_run(**attributes)
    @workspace.investigations.create!(
      { subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
        max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED }.merge(attributes)
    )
  end
end
