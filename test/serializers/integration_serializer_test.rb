require "test_helper"

class IntegrationSerializerTest < ActiveSupport::TestCase
  test "a connection's tools are drawn from the page's preload, not loaded again with their connection per tool" do
    workspace = workspaces(:slack_workspace_one)
    integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    integration.integration_environments.create!(environment: catalog_entries(:production_env))
    %w[restart search_logs list_services].each do |name|
      integration.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    loaded = workspace.integrations.where(id: integration.id).includes(:tools, integration_environments: :environment).to_a

    rows = nil
    seen = queries_sent(cached: true) { rows = IntegrationSerializer.many(loaded).as_json }

    assert_equal %w[list_services restart search_logs], rows.sole["tools"].map { |tool| tool["name"] }
    assert_empty seen.grep(/FROM "integration_tools"|FROM "integrations"|FROM "integration_environments"/)
  end

  test "a tool shows the line a person reads, never the description written for the model" do
    workspace = workspaces(:slack_workspace_one)
    integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    integration.tools.create!(name: "search_logs", description: "Use it after list_resources. At most 200 lines.", read_only: true, enabled: true)
    expected = Integrations::NativePack.for("northflank").tool_definitions.find { |definition| definition.name == "search_logs" }.summary

    tool = IntegrationSerializer.one(integration).as_json["tools"].sole

    assert_equal expected, tool["summary"]
    assert_not tool.key?("description")
  end
end
