require "application_system_test_case"

class WorkflowTriggersTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    @workflow = Workflow.create!(workspace: @workspace, name: "Big incidents")
  end

  test "an incident trigger is chosen from the palette and narrowed with its changes and a condition" do
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    within("aside[aria-label='Add a step']") { click_button "Incident changed" }
    assert_toast "The trigger was updated."

    find("[data-trigger]").click
    within("[data-trigger-settings]") do
      assert_text "Severity"
      find("button[role=combobox]", text: "Add one").click
    end
    find("[role=option]", text: "Resolved").click
    click_button "Add a condition"
    find("button[role=combobox]", text: "What it reads").click
    find("[role=option]", text: "Severity").click
    find("button[role=combobox]", text: "Add a value").click
    find("[role=option]", text: "Critical").click
    take_screenshot
    using_wait_time(10) { assert_no_selector "[data-sonner-toast]" }
    click_button "Apply changes"

    assert_toast "The trigger was updated."
    trigger = @workflow.reload.draft.trigger
    assert_equal Workflow::Trigger::KIND_INCIDENT_CHANGED, trigger["kind"]
    assert_equal [ Workflow::Trigger::Changes::SEVERITY, Workflow::Trigger::Changes::RESOLVED ], trigger["changes"]
    assert_equal [ { "field" => "severity", "operator" => PolicyRule::OPERATOR_IS_ONE_OF, "value" => [ "critical" ] } ], trigger["conditions"]
    assert_text "Only when 1 condition holds"
  end

  test "a step offers what the trigger's data holds as a value to use" do
    @workflow.edit!(operation: Workflow::Edit::OPERATION_CHANGE_TRIGGER, payload: { "trigger" => { "kind" => Workflow::Trigger::KIND_ALERT_RECEIVED, "inputs" => [] } },
                    by: workspace_memberships(:alice_workspace_one))
    @workflow.reload.edit!(operation: Workflow::Edit::OPERATION_ADD_STEP, by: workspace_memberships(:alice_workspace_one),
                           payload: { "step" => { "id" => "tell", "name" => "tell", "kind" => "post_to_channel", "config" => { "channel" => "#ops", "message" => "" } } })
    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow)

    find("[data-step='tell']").click
    find("button[aria-label='Use an earlier value in message']").click

    assert_text "The alert's title"
    assert_text "What routing did"
  end
end
