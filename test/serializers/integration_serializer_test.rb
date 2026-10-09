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

    seen = []
    counter = ->(_, _, _, _, payload) { seen << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    rows = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { IntegrationSerializer.many(loaded).as_json }

    assert_equal %w[list_services restart search_logs], rows.sole["tools"].map { |tool| tool["name"] }
    assert_empty seen.grep(/FROM "integration_tools"|FROM "integrations"|FROM "integration_environments"/)
  end
end
