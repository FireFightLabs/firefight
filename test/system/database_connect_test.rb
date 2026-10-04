require "application_system_test_case"

class DatabaseConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "Neon and Supabase connect with one click to their one server, with no region to choose" do
    { "neon" => [ "Neon", "https://mcp.neon.tech/mcp" ], "supabase" => [ "Supabase", "https://mcp.supabase.com/mcp" ] }.each do |key, (name, server)|
      visit integrations_path(Integration::CONNECT_QUERY_PARAM => key)

      within("[role=dialog]") do
        assert_link "Continue with #{name}"
        assert_no_text "Where your #{name} account is"
        click_button "Use a token instead"
        assert_field "MCP server URL", with: server
      end
      page.save_screenshot(Rails.root.join("tmp/screenshots/#{key}-connect.png"))
    end
  end
end
