require "application_system_test_case"

class NewrelicConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "New Relic asks where the account is and which account each environment reads, on both ways in, and shows both once connected" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "newrelic")

    within("[role=dialog]") do
      assert_text "Account ID"
      assert_text "New Relic lists it in the account picker"
      assert_selector "button[disabled]", text: "Continue with New Relic"
      fill_in "Account ID", with: "1234567"
      find("button[role=combobox]", text: "US (one.newrelic.com)").click
    end
    find("[role=option]", text: "EU (one.eu.newrelic.com)").click
    within("[role=dialog]") do
      href = find_link("Continue with New Relic")[:href]
      assert_includes href, "fields%5Baccount_id%5D=1234567"
      assert_includes href, "region=eu"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/newrelic-connect.png"))

    within("[role=dialog]") do
      click_button "Use a token instead"
      find("#connect-region").click
    end
    find("[role=option]", text: "Japan (one.jp.newrelic.com)").click
    within("[role=dialog]") do
      assert_field "MCP server URL", with: "https://mcp.jp.newrelic.com/mcp/"
      fill_in "Account ID", with: ""
      assert_button "Connect & discover tools", disabled: true
      fill_in "Account ID", with: "7654321"
      assert_button "Connect & discover tools", disabled: false
    end
    find("body").send_keys(:escape)

    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "newrelic", name: "New Relic",
                                                  settings: { "server_url" => "https://mcp.eu.newrelic.com/mcp/", "region" => "eu" })
    integration.integration_environments.create!.store_fields!("account_id" => "1234567")
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)
    assert_text "Region EU (one.eu.newrelic.com)"
    assert_text "Account ID 1234567"
    page.save_screenshot(Rails.root.join("tmp/screenshots/newrelic-connected.png"))
  end
end
