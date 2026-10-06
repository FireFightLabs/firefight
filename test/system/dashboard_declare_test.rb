require "application_system_test_case"

class DashboardDeclareTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "declare incident sits in the page header and opens the declare form" do
    visit root_path

    within("header") { click_on "Declare incident" }

    assert_selector "[role='dialog']"
    page.save_screenshot(Rails.root.join("tmp/screenshots/dashboard-declare-in-header.png"))
  end
end
