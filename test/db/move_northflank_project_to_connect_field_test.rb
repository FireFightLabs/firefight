require "test_helper"
require Rails.root.join("db/migrate/20261004120000_move_northflank_project_to_connect_field")

class MoveNorthflankProjectToConnectFieldTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(
      catalog_entry_id: catalog_entries(:production_env).id,
      credentials: { "api_token" => "nf-token", "project" => " firefight " }.to_json,
      base_config: { IntegrationEnvironment::LEARNED_KEY => { "kept" => true } }
    )
    @empty = northflank.integration_environments.create!(credentials: { "api_token" => "nf-other" }.to_json)
    @other = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "sentry", name: "Sentry", settings: { "server_url" => "https://mcp.sentry.dev/mcp" })
                       .integration_environments.create!(credentials: { "project" => "web" }.to_json)
  end

  test "a Northflank project moves from the credentials to the connect fields, keeps everything else, and moves back" do
    migrate(:up)

    @row.reload
    assert_equal({ "api_token" => "nf-token" }, @row.credentials_hash)
    assert_equal({ "project" => "firefight" }, @row.fields)
    assert_equal({ "kept" => true }, @row.learned)
    assert_equal "firefight", Integrations::ConnectionSettings.of(@row).field(Integrations::Packs::Northflank::PROJECT)
    assert_equal({ "api_token" => "nf-other" }, @empty.reload.credentials_hash)
    assert_equal({ "project" => "web" }, @other.reload.credentials_hash, "another provider's credentials are left alone")

    migrate(:down)
    @row.reload
    assert_equal({ "api_token" => "nf-token", "project" => "firefight" }, @row.credentials_hash)
    assert_empty @row.fields
  end

  private

  def migrate(direction) = ActiveRecord::Migration.suppress_messages { MoveNorthflankProjectToConnectField.new.migrate(direction) }
end
