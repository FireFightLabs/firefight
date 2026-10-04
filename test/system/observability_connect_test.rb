require "application_system_test_case"

class ObservabilityConnectTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "Axiom asks for its organization and datasets before it connects, with traces optional, and shows them once connected" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "axiom")

    within("[role=dialog]") do
      assert_text "Traces dataset (optional)"
      assert_selector "button[disabled]", text: "Continue with Axiom"
      fill_in "Organization ID", with: "acme"
      fill_in "Logs dataset", with: "logs"
      assert_selector "a[href*='fields%5Blogs_dataset%5D=logs']", text: "Continue with Axiom"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/axiom-connect.png"))
    find("body").send_keys(:escape)

    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "axiom", name: "Axiom", settings: { "server_url" => "https://mcp.axiom.co/mcp" })
    integration.integration_environments.create!(base_config: { IntegrationEnvironment::FIELDS_KEY => { "org_id" => "acme", "logs_dataset" => "logs" } })
    visit integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)
    assert_text "Logs dataset logs"
    assert_no_text "Traces dataset"
    page.save_screenshot(Rails.root.join("tmp/screenshots/axiom-connected.png"))
  end

  test "Honeycomb asks which environment the connection reads" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "honeycomb")

    within("[role=dialog]") do
      assert_text "as Honeycomb's address shows it after /environments/"
      assert_selector "button[disabled]", text: "Continue with Honeycomb"
      fill_in "Environment", with: "production"
      assert_selector "a[href*='fields%5Benvironment_slug%5D=production']", text: "Continue with Honeycomb"
    end
  end

  test "Honeybadger and SigNoz offer each region their hosted servers run in, so an EU or India account can connect" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "honeybadger")
    within("[role=dialog]") { find("button[role=combobox]", text: "US (app.honeybadger.io)").click }
    find("[role=option]", text: "EU (eu-app.honeybadger.io)").click
    within("[role=dialog]") { assert_includes find_link("Continue with Honeybadger")[:href], "region=eu" }
    page.save_screenshot(Rails.root.join("tmp/screenshots/honeybadger-region.png"))
    find("body").send_keys(:escape)

    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "signoz")
    within("[role=dialog]") do
      click_button "Use a token instead"
      find("#connect-region").click
    end
    find("[role=option]", text: "India").click
    within("[role=dialog]") { assert_field "MCP server URL", with: "https://mcp.in.signoz.cloud/mcp" }
  end
end
