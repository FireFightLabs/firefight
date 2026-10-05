require "application_system_test_case"

class IncidentFollowUpIssueTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
  end

  test "a follow-up tracked in an issue tracker links to the issue from the incident page" do
    @incident.incident_actions.create!(
      created_by: workspace_memberships(:alice_workspace_one), action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
      description: "Investigate automated probing against web service", external_key: "FIR-105",
      external_url: "https://linear.app/firefight/issue/FIR-105/investigate-automated-probing-against-web-service"
    )

    visit incident_path(@incident)

    assert_text "Investigate automated probing against web service"
    link = find_link("FIR-105")
    assert_equal "https://linear.app/firefight/issue/FIR-105/investigate-automated-probing-against-web-service", link[:href]
    assert_equal "_blank", link[:target]
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-follow-up-issue.png"))
  end
end
