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

  test "a pack's credentials form asks its connect fields, with a list to choose several from" do
    northflank = IntegrationProvider.find("northflank")
    regions = IntegrationProvider::ConnectField.new(key: "regions", label: "Regions", hint: "The regions this account runs in.", multiple: true,
                                                    options: [ { "value" => "us-east-1", "label" => "US East (N. Virginia)" },
                                                               { "value" => "eu-west-1", "label" => "Europe (Ireland)" } ])
    entries = IntegrationProvider.all.map { |entry| entry.key == "northflank" ? northflank.with(connect_fields: [ regions ]) : entry }
    IntegrationProvider.stubs(:all).returns(entries)

    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "northflank")
    within("[role=dialog]") do
      assert_text "The regions this account runs in."
      click_button "Choose regions"
    end
    find("[role=option]", text: "Europe (Ireland)").click
    find("[role=option]", text: "US East (N. Virginia)").click
    find("body").send_keys(:escape)

    within("[role=dialog]") do
      assert_text "Europe (Ireland)"
      assert_text "US East (N. Virginia)"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-connect-fields-multiple.png"))
  end
end
