require "application_system_test_case"

class IntegrationRegionTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "a provider with several regions asks which one, on one-click connect and on the token form, and the connection shows it" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "datadog")

    within("[role=dialog]") do
      assert_text "Where your Datadog account is"
      assert_text "US1 (app.datadoghq.com)"
      find("button[role=combobox]", text: "US1 (app.datadoghq.com)").click
    end
    find("[role=option]", text: "EU1 (app.datadoghq.eu)").click
    within("[role=dialog]") do
      assert_includes find_link("Continue with Datadog")[:href], "region=eu1"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-region.png"))

    within("[role=dialog]") do
      click_button "Use a token instead"
      find("#connect-region").click
    end
    find("[role=option]", text: "UK1 (uk1.datadoghq.com)").click
    within("[role=dialog]") { assert_field "MCP server URL", with: "https://mcp.uk1.datadoghq.com/v1/mcp" }
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-region-token.png"))

    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.eu/v1/mcp", "region" => "eu1" })
    datadog.integration_environments.create!
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => datadog.id)

    assert_text "Region EU1 (app.datadoghq.eu)"
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-region-connected.png"))
  end

  test "a provider with one region asks nothing about it" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "linear")

    within("[role=dialog]") do
      assert_text "Connect Linear"
      assert_no_text "Region"
    end
  end
end
