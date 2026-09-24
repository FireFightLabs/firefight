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
      max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED,
      created_at: 140.seconds.ago, started_at: 133.seconds.ago, completed_at: Time.current, turns_used: 13,
      brief: { Investigation::Brief::KEY_SYMPTOM => "The billing page shows Something went wrong for every admin" }
    )
    @investigation.note_started!
    @investigation.record_hypothesis!(assertion: "A deploy changed the billing plan lookup").update!(created_at: 125.seconds.ago)
    changes = step(1, "Changes before 14:02 in acme/cloud", "3 commits, none touching billing", 120)
    @investigation.record_hypothesis!(assertion: "The billing page calls a method nothing defines").update!(created_at: 105.seconds.ago)
    read = step(2, "Read app/controllers/billing_controller.rb", "before_action :require_admin!", 100)
    step(3, "Find where require_admin! is defined", "require_admin! is not defined in acme/cloud, acme/app.", 80)
    @investigation.record_hypothesis!(assertion: "A deploy changed the billing plan lookup", status: Investigation::Hypothesis::STATUS_REFUTED, steps: [ changes.position ])
    @investigation.record_hypothesis!(assertion: "The billing page calls a method nothing defines", status: Investigation::Hypothesis::STATUS_SUPPORTED, confidence: 0.9, steps: [ 2, 3 ])
    finding = @investigation.conclude!(
      summary: "The billing controller runs before_action :require_admin!, which is defined nowhere, so every signed in visit fails.",
      hypothesis_assertion: "The billing page calls a method nothing defines",
      evidence: [ { claim: "The controller calls require_admin! before every action", steps: [ read.position ] },
                  { claim: "Nothing in either repository defines it", steps: [ 3 ] } ],
      gaps: "Production logs, since none are connected"
    )
    @investigation.note_answered!(finding)
  end

  test "a run opens from the incident's timeline and tells what it was asked, what it found and how" do
    visit incident_path(@incident)
    assert_text "found"
    click_link "an answer"

    within("[role=dialog]") do
      assert_text "The billing page shows Something went wrong for every admin"
      assert_selector "h3", text: /why it thinks so/i
      assert_text "Ruled out"
      assert_text "Find where require_admin! is defined"
      click_button "Show what it returned", match: :first
      assert_text "3 commits, none touching billing"
    end
    assert_current_path incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-sheet.png"))

    find("[role=dialog] button", text: /close/i, visible: :all).click
    assert_no_selector "[role=dialog]"
    assert_current_path incident_path(@incident)
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-timeline-investigation.png"))
  end

  test "the run's own link, the one Slack carries, opens it over its incident" do
    visit investigation_path(@investigation)

    within("[role=dialog]") { assert_text "The billing controller runs before_action :require_admin!" }
    assert_text @incident.name
  end

  private

  def step(position, label, result, seconds_ago)
    step = @investigation.steps.create!(
      position: position, tool_name: "github_tool", label: label, action_key: "github.tool",
      status: Investigation::Step::STATUS_RUNNING, started_at: seconds_ago.seconds.ago
    )
    step.succeed!(compacted_result: result)
    step.update!(completed_at: (seconds_ago - 3).seconds.ago)
    step
  end
end
