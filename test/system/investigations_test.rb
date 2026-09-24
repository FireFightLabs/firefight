require "application_system_test_case"

class InvestigationsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED, spent_micros: 1_323_000,
      started_at: 133.seconds.ago, completed_at: Time.current, turns_used: 13,
      brief: { Investigation::Brief::KEY_SYMPTOM => "The billing page shows Something went wrong" }
    )
    read = step(1, "Github fetch file billing_controller.rb", "before_action :require_admin!")
    step(2, "Github find definition require_admin!", "require_admin! is not defined in acme/cloud, acme/app.")
    @investigation.record_hypothesis!(assertion: "The billing page calls a method nothing defines", status: Investigation::Hypothesis::STATUS_SUPPORTED, steps: [ 1, 2 ])
    @investigation.conclude!(
      summary: "The billing controller runs before_action :require_admin!, which is defined nowhere, so every signed in visit fails.",
      hypothesis_assertion: "The billing page calls a method nothing defines",
      evidence: [ { claim: "The controller calls require_admin! before every action", steps: [ read.position ] },
                  { claim: "Nothing in either repository defines it", steps: [ 2 ] } ],
      gaps: "Production logs, since none are connected"
    )
  end

  test "the list shows the run, and the run shows its finding, its theories and every step" do
    visit investigations_path

    assert_text @incident.identifier
    assert_text "Answered"
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigations-list.png"))

    click_link @incident.identifier

    assert_text "What it found"
    assert_selector "h3", text: /why it thinks so/i
    assert_text "The billing page calls a method nothing defines"
    assert_text "Github find definition require_admin!"
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation.png"))

    click_button "Show what it returned", match: :first
    assert_text "before_action :require_admin!"
  end

  test "an incident with several runs opens the list of them, and one run opens directly" do
    visit incident_path(@incident)
    click_link "Investigation"
    assert_text "What it found"

    @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400,
      status: Investigation::STATUS_FAILED, error_summary: Investigation::BUDGET_SPENT
    )
    visit incident_path(@incident)
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-header.png"))
    find("a[href=\"#{investigations_path(incident_id: @incident.id)}\"]").click

    assert_text "#{@incident.identifier} investigations"
    assert_text Investigation::BUDGET_SPENT
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-investigations.png"))
  end

  private

  def step(position, label, result)
    step = @investigation.steps.create!(
      position: position, tool_name: "github_tool", label: label, action_key: "github.tool",
      status: Investigation::Step::STATUS_RUNNING, started_at: 3.seconds.ago
    )
    step.succeed!(compacted_result: result)
    step
  end
end
