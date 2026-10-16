require "application_system_test_case"

class PostmortemTaskListTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    @incident = Incident.create!(
      workspace: @workspace, declared_by: @member, incident_status: incident_statuses(:resolved_ws1),
      incident_severity: incident_severities(:minor_ws1), name: "Checkout failing", is_private: false,
      resolved_at: Time.current, source: Incident::SOURCE_SLACK
    )
    postmortem = Postmortem.start_blank!(@incident, by: @member)
    postmortem.update_content!("<h2>Follow-ups</h2><p>Next</p>", by: @member, expected_version: postmortem.content_version)
    sign_in(users(:alice), @workspace)
  end

  test "a task list typed in the editor keeps its checkboxes and ticks once saved and opened again" do
    visit incident_postmortem_path(@incident)
    editor = find(".postmortem-content")
    editor.find("p", text: "Next").click
    editor.send_keys(:end, :enter, "[ ] Roll back the deploy", :enter, "Add an alert on timeouts")
    editor.find("li", text: "Roll back the deploy").find("input[type='checkbox']").click
    assert_text "Saved", wait: 10

    refresh

    items = find(".postmortem-content").all("ul[data-type='taskList'] > li", count: 2)
    assert_equal [ "Roll back the deploy", "Add an alert on timeouts" ], items.map { |item| item.find("div").text }
    assert_equal %w[true false], items.map { |item| item["data-checked"] }
    assert_equal [ true, false ], items.map { |item| item.find("input[type='checkbox']").checked? }
    page.save_screenshot(Rails.root.join("tmp/screenshots/postmortem-task-list.png"))

    click_on "Revisions"
    click_on "Edited", match: :first
    within("[role='dialog']") { assert_selector "ul[data-type='taskList'] input[type='checkbox']", count: 2 }
    page.save_screenshot(Rails.root.join("tmp/screenshots/postmortem-task-list-revision.png"))
  end
end
