require "application_system_test_case"

class RunbookDetailMarkdownTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    @runbook = @workspace.runbooks.create!(
      name: "Database outage", summary: "Restore writes",
      content: "## Before you start\n\nCheck the **primary** first.\n\n- Read the replica lag\n- Page the DBA\n\nSee [the status page](https://status.example.com)."
    )
    sign_in(users(:alice), @workspace)
  end

  test "the detail panel renders the runbook's markdown rather than showing it raw" do
    visit settings_runbooks_path(Runbook::QUERY_PARAM => @runbook.id)

    within("[role='dialog']") do
      assert_selector "h2", text: "Before you start"
      assert_selector "strong", text: "primary"
      assert_selector "li", text: "Read the replica lag"
      assert_selector "a[href='https://status.example.com'][target='_blank'][rel='noopener noreferrer']", text: "the status page"
      assert_no_text "**primary**"
      assert_no_text "## Before you start"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/runbook-detail-markdown.png"))
  end
end
