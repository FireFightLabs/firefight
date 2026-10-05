require "test_helper"

class Integrations::Capabilities::PostgresTest < ActiveSupport::TestCase
  Capabilities = Integrations::Capabilities

  setup do
    @workspace = workspaces(:slack_workspace_one)
    postgres = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "postgresql", name: "Orders DB", slug: "orders_db")
    @row = postgres.integration_environments.create!
    postgres.tools.create!(name: "database_status", description: "Status", read_only: true, enabled: true, params_schema: { "type" => "object" })
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "postgresql", account: "db.example.com", kind: ResourceMap::KIND_DATABASE, external_id: "db.example.com:5432/orders", name: "orders")
    ]))
  end

  test "a database reached by its URL answers its status through the pack, on the connection that reaches it" do
    call = Capabilities.resolve(@workspace, Capabilities::STATUS, "resource" => "orders")

    assert_equal [ @row, "database_status", {} ], [ call.environment_row, call.tool.name, call.arguments ]
  end

  test "it answers nothing it has no source for" do
    %w[logs metrics deploys restart].each do |key|
      error = assert_raises(Capabilities::Unroutable) { Capabilities.resolve(@workspace, key, "resource" => "orders") }
      assert_match "no connection offers", error.message
    end
  end
end
