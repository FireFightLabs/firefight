require "application_system_test_case"

class SentryConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "one-click connect asks the organization and an optional project, and they shape the server's address" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "sentry")

    within("[role=dialog]") do
      assert_text "Connect Sentry"
      assert_text "Its slug, under Settings, General Settings in Sentry"
      assert_text "Leave it empty to reach every project"
      fill_in "Organization", with: "acme"
      fill_in "Project", with: "checkout"
      href = find_link("Continue with Sentry")[:href]
      assert_includes href, "fields%5Borganization%5D=acme"
      assert_includes href, "fields%5Bproject%5D=checkout"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/sentry-connect.png"))
  end
end
