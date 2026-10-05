require "application_system_test_case"

class DatabaseProvidersConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "ClickHouse, Turso and Upstash connect in one click with their own sign in, and ask no region" do
    { "clickhouse" => "ClickHouse", "turso" => "Turso", "upstash" => "Upstash" }.each do |key, name|
      visit integrations_path(Integration::CONNECT_QUERY_PARAM => key)

      within("[role=dialog]") do
        assert_text "Connect #{name}"
        assert_link "Continue with #{name}"
        assert_no_text "Region"
      end
      page.save_screenshot(Rails.root.join("tmp/screenshots/connect-#{key}.png"))
    end
  end
end
