require "application_system_test_case"

class IncidentTimelineUpdateTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
  end

  test "an update reads as paragraphs, a list and links on the timeline" do
    message = "Findings so far:\n\n" \
              "- Automated probing was observed today against **web**.\n" \
              "- Requests returned `404`. No successful access was found.\n" \
              "- Linear follow-up: [FIR-105](https://linear.app/firefight/issue/FIR-105)\n\n" \
              "Next update once the rule is live.\nWatching the edge logs until then."
    @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: workspace_memberships(:alice_workspace_one), message: message)

    visit incident_path(@incident)

    assert_text "Findings so far:"
    list = find(:xpath, "//ul[li[contains(., 'Automated probing')]]")
    assert_equal 3, list.all("li").size
    assert_selector "strong", text: "web"
    assert_selector "code", text: "404"
    link = find_link("FIR-105")
    assert_equal "https://linear.app/firefight/issue/FIR-105", link[:href]
    assert_equal "_blank", link[:target]
    assert_equal "noopener noreferrer", link[:rel]
    paragraph = find("p", text: "Next update once the rule is live.")
    assert_operator paragraph.evaluate_script("Math.round(this.offsetHeight / parseFloat(getComputedStyle(this).lineHeight))"), :>=, 2

    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-timeline-update.png"))
  end

  test "an update written with bullet characters before lists keeps one bullet per line" do
    message = "Traffic-path assessment:\n\n• The probes came through Cloudflare.\n• The origin port is public.\n• Restrict the origin to Cloudflare."
    @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: workspace_memberships(:alice_workspace_one), message: message)

    visit incident_path(@incident)

    bullets = find("p", text: "• The probes came through Cloudflare.")
    assert_operator bullets.evaluate_script("Math.round(this.offsetHeight / parseFloat(getComputedStyle(this).lineHeight))"), :>=, 3
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-timeline-legacy-update.png"))
  end

  test "raw html in an update is never rendered" do
    message = "Done <script>window.injected = true</script> <img src=x onerror=\"window.injected = true\">"
    @incident.record_change!(IncidentEvent::INCIDENT_UPDATED, by: workspace_memberships(:alice_workspace_one), message: message)

    visit incident_path(@incident)

    assert_text "Done"
    assert_no_selector "img[src=x]", visible: :all
    assert_nil page.evaluate_script("window.injected")
  end
end
