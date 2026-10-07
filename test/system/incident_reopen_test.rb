require "application_system_test_case"

class IncidentReopenTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:resolved_minor_ws1)
    sign_in(users(:alice), @workspace)
  end

  test "reopening from the dashboard asks for the optional reason Slack asks for, and records it" do
    visit incident_path(@incident)
    click_button "Incident actions"
    find("[role=menuitem]", text: "Reopen incident").click

    within("[role=dialog]") do
      assert_text "Reason for reopening"
      assert_text "(optional)"
      assert_equal Incident::REOPEN_REASON_LIMIT.to_s, find_field("Reason for reopening")[:maxlength]
      fill_in "Reason for reopening", with: "Uploads are failing again for large images"
      page.save_screenshot(Rails.root.join("tmp/screenshots/incident-reopen-dialog.png"))
      click_button "Reopen incident"
    end

    assert_text "#{@incident.identifier} was reopened."
    assert_no_selector "[role=dialog]"
    event = @incident.incident_events.find_by!(event_type: IncidentEvent::INCIDENT_REOPENED)
    assert_equal "Uploads are failing again for large images", event.metadata["reason"]
    assert_equal @workspace.default_live_status, @incident.reload.incident_status
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-reopened.png"))
  end

  test "Never mind leaves the incident closed" do
    visit incident_path(@incident)
    click_button "Incident actions"
    find("[role=menuitem]", text: "Reopen incident").click
    click_button "Never mind"

    assert_no_selector "[role=dialog]"
    assert @incident.reload.terminal?
  end
end
