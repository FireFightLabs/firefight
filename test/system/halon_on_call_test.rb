require "application_system_test_case"

class HalonOnCallTest < ApplicationSystemTestCase
  include OnCallTestHelper

  setup do
    alert_run_with_restart_fix
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
  end

  test "an admin turns on alert runs and adds an unattended rule, each with a toast, and the row says what is missing" do
    visit halon_on_call_path

    find("#alert-runs").click
    click_button "Save"
    assert_text "On-call settings were updated."
    assert @workspace.reload.alert_investigations_enabled

    click_button "Add rule"
    find("#unattended-capability").click
    find("[role=option]", text: "Restart").click
    find("#unattended-resource").click
    find("[role=option]", text: "web").click
    fill_in "unattended-threshold", with: "50"
    within("[role=dialog]") { click_button "Add rule" }

    assert_text "Unattended rule to restart web was created."
    assert_text "Restart web when the average of its errors over the last 10 minutes is above 50."
    assert_text "holds no grant of Northflank's api_request"
    page.save_screenshot(Rails.root.join("tmp/screenshots/halon-on-call.png"))
  end

  test "an approval rule lets whoever is on call approve, from the Permissions page" do
    visit gateway_permissions_path

    click_button "Rules"
    click_button "Add rule"
    find("#on-call-may-approve").click
    click_button "Create rule"

    assert_text "Approval rule was created."
    assert_text "or whoever is on call for the incident"
    assert @workspace.approval_rules.sole.outcome.dig("require", PolicyRule::ApprovalOutcome::ON_CALL)
  end
end
