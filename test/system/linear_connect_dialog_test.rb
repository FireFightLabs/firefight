require "application_system_test_case"

# Linear connects only through Firefight's own app, which the connect dialog offers in place of signing in. Other
# providers' dialogs are as they were.
class LinearConnectDialogTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"], @previous = "lin-app", ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"]
  end

  teardown { ENV["INTEGRATION_LINEAR_APP_CLIENT_ID"] = @previous }

  def open_dialog(provider)
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => provider)
    find("[role=dialog]")
  end

  test "Linear offers one way in, Firefight's own app, with a token as the small alternative" do
    within(open_dialog("linear")) do
      assert_text "Connect Linear"
      assert_text "Halon reads and updates issues as Firefight, keeps incident follow-ups in step and answers when someone assigns or mentions Firefight."
      assert_text "A Linear admin approves Firefight's app on Linear's screen. No keys to copy."
      link = find_link("Continue with Linear")
      assert_equal "true", Rack::Utils.parse_query(URI.parse(link[:href]).query)["app"]
      assert_no_text "Firefight's own Linear app"
      assert_no_text "consent screen"
      assert_no_button "Add a second account"
      assert_button "Use a token instead"
      page.save_screenshot(Rails.root.join("tmp/screenshots/linear-connect-dialog.png"))

      click_button "Use a token instead"
      assert_field "connect-auth"
    end
  end

  test "once Linear is connected the dialog offers a second account" do
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear",
                                    settings: { "server_url" => "https://mcp.linear.app/mcp", Integration::APP_SETTING => true })

    within(open_dialog("linear")) do
      assert_text "Add a Linear connection"
      assert_link "Continue with Linear"
      click_button "Add a second account"
      fill_in placeholder: "e.g. Linear Payments", with: "Linear Payments"
      query = Rack::Utils.parse_query(URI.parse(find_link("Continue with Linear")[:href]).query)
      assert_equal [ "true", "Linear Payments" ], query.values_at("app", "name")
      page.save_screenshot(Rails.root.join("tmp/screenshots/linear-connect-dialog-second.png"))
    end
  end

  test "a provider reached through its MCP server alone keeps its sign-in, second account and token links" do
    within(open_dialog("notion")) do
      link = find_link("Continue with Notion")
      assert_nil Rack::Utils.parse_query(URI.parse(link[:href]).query)["app"]
      assert_text "You approve access on Notion's consent screen. No keys to copy."
      assert_button "Add a second account"
      assert_button "Use a token instead"
      page.save_screenshot(Rails.root.join("tmp/screenshots/notion-connect-dialog.png"))
    end
  end
end
