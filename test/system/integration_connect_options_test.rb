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

    assert_text "Grafana now uses Loki US for logs datasource."
    assert_equal "b2", row.reload.fields["logs_source"]
    page.save_screenshot(Rails.root.join("tmp/screenshots/integration-learned-choice.png"))
  end
end
