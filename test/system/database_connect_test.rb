require "application_system_test_case"

class DatabaseConnectTest < ApplicationSystemTestCase
  setup do
    sign_in(users(:alice), workspaces(:slack_workspace_one))
  end

  test "Neon and Supabase connect with one click to their one server, with no region to choose" do
    { "neon" => [ "Neon", "https://mcp.neon.tech/mcp" ], "supabase" => [ "Supabase", "https://mcp.supabase.com/mcp" ] }.each do |key, (name, server)|
      visit integrations_path(Integration::CONNECT_QUERY_PARAM => key)

      within("[role=dialog]") do
        assert_text "Continue with #{name}"
        assert_no_text "Where your #{name} account is"
        click_button "Use a token instead"
        assert_field "MCP server URL", with: server
      end
      page.save_screenshot(Rails.root.join("tmp/screenshots/#{key}-connect.png"))
    end
  end

  test "Supabase asks which project and what access on one-click connect, and puts them in the server's address" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "supabase")

    within("[role=dialog]") do
      assert_button "Continue with Supabase", disabled: true
      assert_field "Project"
      assert_text "Read only leaves out every tool that changes the database or the project."
      fill_in "Project", with: "abcdefghijklmnopqrst"
      find("#connect-read_only").click
    end
    find("[role=option]", text: "Read only").click
    page.save_screenshot(Rails.root.join("tmp/screenshots/supabase-connect-fields.png"))
    within("[role=dialog]") do
      href = find_link("Continue with Supabase")[:href]
      assert_includes href, "abcdefghijklmnopqrst"
      assert_includes href, "read_only"
    end
  end
end
