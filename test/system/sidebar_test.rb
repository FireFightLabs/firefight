require "application_system_test_case"

class SidebarTest < ApplicationSystemTestCase
  SHORT = [ 1400, 600 ].freeze

  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
    page.driver.browser.manage.window.resize_to(*SHORT)
  end

  test "the sidebar keeps its scroll when a link in it opens another page" do
    visit settings_severities_path
    page.execute_script("document.querySelector('[data-slot=sidebar-content]').scrollTop = 10000")
    scrolled = page.evaluate_script("document.querySelector('[data-slot=sidebar-content]').scrollTop")
    assert_operator scrolled, :>, 0, "the window is too tall for the sidebar to scroll"

    within("[data-slot=sidebar-content]") { click_link "Integrations" }
    assert_current_path integrations_path

    assert_equal scrolled, page.evaluate_script("document.querySelector('[data-slot=sidebar-content]').scrollTop")
  end
end
