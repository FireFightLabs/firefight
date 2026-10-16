require "application_system_test_case"

class IntegrationConnectOptionsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "a pasted key is a text area, and a provider with its own MCP server offers it instead of credentials and back" do
    northflank = IntegrationProvider.find("northflank").with(server_url: "https://mcp.northflank.example/mcp")
    entries = IntegrationProvider.all.map { |entry| entry.key == "northflank" ? northflank : entry }
    IntegrationProvider.stubs(:all).returns(entries)
    key = Integrations::NativePack::CredentialField.new(key: "service_account_key", label: "Service account key", secret: true, multiline: true,
                                                        placeholder: "{ \"type\": \"service_account\", ... }", hint: "The JSON key of a service account.")
    Integrations::Packs::Northflank.stubs(:credential_fields).returns([ key ])

    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "northflank")
    within("[role=dialog]") do
      assert_selector "textarea#connect-service_account_key"
      assert_text "The JSON key of a service account. Stored encrypted, never shown again."
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-multiline-credential.png"))

    within("[role=dialog]") do
      click_button "Use an MCP server instead"
      assert_includes find_link("Continue with Northflank")[:href], "kind=mcp"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-mcp-alternative.png"))

    within("[role=dialog]") do
      click_button "Back to credentials"
      assert_selector "textarea#connect-service_account_key"
    end
  end

  test "Grafana signs in to a Grafana Cloud stack, says which access to leave off, and a server a team runs is pasted with a token" do
    visit integrations_path(Integration::CONNECT_QUERY_PARAM => "grafana")
    within("[role=dialog]") do
      assert_text "Stack address"
      assert_text "On Grafana's screen, leave Write access and Query access off so Firefight can only read."
      assert_selector "a", text: "Continue with Grafana", count: 0
      fill_in "Stack address", with: "mystack.grafana.net"
      href = find_link("Continue with Grafana")[:href]
      assert_includes href, "fields%5Bstack%5D=mystack.grafana.net"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/grafana-sign-in.png"))

    within("[role=dialog]") do
      click_button "Use a server you run"
      assert_equal "", find_field("MCP server URL").value
      assert_equal "https://mcp-grafana.example.com/mcp", find_field("MCP server URL")[:placeholder]
      assert_text "Paste the address of the mcp-grafana server you run"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/grafana-own-server.png"))
  end

  test "a Grafana sign-in that ended shows on the connection with how to sign in again" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana",
                                                  settings: { "server_url" => "https://mcp.grafana.com/mcp/mystack.grafana.net", "fields" => { "stack" => "mystack.grafana.net" } })
    row = integration.integration_environments.create!
    row.record_health!(false, error: "The sign-in to Grafana has ended, so Firefight can no longer reach it. Open its details, choose Add connection and sign in again under the name Grafana.")

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)
    assert_text "The sign-in to Grafana has ended"
    page.save_screenshot(Rails.root.join("tmp/screenshots/grafana-sign-in-ended.png"))
    click_button "Add connection"
    within("[role=dialog]") do
      assert_text "Add a Grafana connection"
      fill_in "Stack address", with: "mystack.grafana.net"
      assert_includes find_link("Continue with Grafana")[:href], "name=Grafana"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/grafana-sign-in-again.png"))
  end

  test "a value the connection learned to choose from is chosen on its details, with a toast" do
    logs = IntegrationProvider::ConnectField.new(key: "logs_source", label: "Logs datasource", hint: "Which Loki datasource holds its logs.", learned: "loki")
    grafana = IntegrationProvider.find("grafana").with(connect_fields: [ logs ])
    entries = IntegrationProvider.all.map { |entry| entry.key == "grafana" ? grafana : entry }
    IntegrationProvider.stubs(:all).returns(entries)
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "grafana", name: "Grafana", settings: { "server_url" => "https://gf.example/mcp" })
    row = integration.integration_environments.create!
    row.store_learned!("loki" => [ { "value" => "a1", "label" => "Loki EU" }, { "value" => "b2", "label" => "Loki US" } ])

    visit integrations_path(Integration::DETAILS_QUERY_PARAM => integration.id)
    assert_text "Which Loki datasource holds its logs."
    find("button[aria-label='Logs datasource']").click
    find("[role=option]", text: "Loki US").click

    assert_toast "Grafana now uses Loki US for logs datasource."
    assert_equal "b2", row.reload.fields["logs_source"]
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-learned-choice.png"))
  end
end
