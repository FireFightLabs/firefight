require "application_system_test_case"

class HostingConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "Trigger.dev, Convex and Modal ask for their secret beside the plain settings the form checks" do
    { "trigger_dev" => [ "Secret API key", "Project ref" ], "convex" => [ "Deploy key", "Deployment URL" ],
      "modal" => [ "Token ID", "Token secret", "Environment" ] }.each do |key, labels|
      visit integrations_path(Integration::CONNECT_QUERY_PARAM => key)

      within("[role=dialog]") { labels.each { |label| assert_text label } }
      page.save_screenshot(Rails.root.join("tmp/screenshots/connect-#{key}.png"))
    end
  end
end
