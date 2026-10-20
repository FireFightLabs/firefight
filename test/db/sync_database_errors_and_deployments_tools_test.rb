require "test_helper"
require Rails.root.join("db/migrate/20261020170100_sync_database_errors_and_deployments_tools")

class SyncDatabaseErrorsAndDeploymentsToolsTest < ActiveSupport::TestCase
  test "existing Tinybird and PostgreSQL connections get the new reads, and keep the tools they had as they were" do
    workspace = workspaces(:slack_workspace_one)
    added = { "tinybird" => "deployments", "postgresql" => "database_errors" }
    connections = added.keys.to_h do |provider|
      [ provider, workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: provider.humanize, slug: "de_#{provider}") ]
    end
    kept = connections["postgresql"].tools.create!(name: "run_query", description: "Query", read_only: true, enabled: false, params_schema: { "type" => "object" })

    ActiveRecord::Migration.suppress_messages { SyncDatabaseErrorsAndDeploymentsTools.new.up }

    added.each do |provider, name|
      tool = connections[provider].tools.find_by!(name: name)
      assert tool.enabled, "#{provider}'s new tool arrives switched on"
      assert tool.read_only, "#{provider}'s new tool only reads"
    end
    assert_not kept.reload.enabled, "an admin's choice stays"
  end
end
