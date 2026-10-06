require "test_helper"

module Integrations
  class NamedTest < ActiveSupport::TestCase
    ROWS = [ { id: "app-1", name: "Web" }, { id: "app-2", name: "worker" }, { id: "db-1", name: "shared" }, { id: "db-2", name: "shared" } ].freeze

    test "a row is found by its id first, then by a name only it has, whatever the case" do
      assert_equal "app-1", Named.find(ROWS, " APP-1 ", id: :id, name: :name, provider: "Acme")[:id]
      assert_equal "app-1", Named.find(ROWS, "web", id: :id, name: :name, provider: "Acme")[:id]
      assert_nil Named.find(ROWS, "nothing", id: :id, name: :name, provider: "Acme")
      assert_nil Named.find(ROWS, " ", id: :id, name: :name, provider: "Acme")
    end

    test "a name two rows share is refused with each one's id, never picked" do
      error = assert_raises(Named::Ambiguous) { Named.find(ROWS, "shared", id: :id, name: :name, provider: "Acme") }

      assert_equal "More than one Acme resource is called shared: db-1, db-2. Name it by its id.", error.message
      assert_kind_of NativePack::Error, error
      assert_equal "db-2", Named.find(ROWS, "db-2", id: :id, name: :name, provider: "Acme")[:id], "an id still finds one of them"
    end

    test "a refusal read through a connection names the connection and each row's id on the map" do
      workspace = workspaces(:slack_workspace_one)
      integration = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Faylee")
      row = integration.integration_environments.create!
      mapped = ResourceMap::Resource.create!(workspace: workspace, provider: "northflank", account: "team/faylee", kind: ResourceMap::KIND_DATABASE,
                                             external_id: "db-1", name: "shared", integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)

      error = assert_raises(Named::Ambiguous) { Named.find(ROWS, "shared", id: :id, name: :name, provider: "Northflank", connection: row) }

      assert_equal "More than one Northflank resource in Faylee (Northflank) is called shared: db-1 (map id #{mapped.id}), db-2. Name it by its id.", error.message
    end

    test "rows with string keys or objects are read the same way, and a refusal can name each row its own way" do
      rows = [ { "id" => 7, "label" => "api" }, { "id" => 8, "label" => "api" } ]
      error = assert_raises(Named::Ambiguous) do
        Named.find(rows, "api", id: "id", name: ->(row) { row["label"] }, provider: "Acme", describe: ->(row) { "Droplet #{row['id']}" })
      end
      assert_equal "More than one Acme resource is called api: Droplet 7, Droplet 8. Name it by its id.", error.message
      assert_equal 7, Named.find(rows, "7", id: "id", name: "label", provider: "Acme")["id"]

      record = Data.define(:id, :name).new(id: "x1", name: "Box")
      assert_equal record, Named.find([ record ], "box", id: :id, name: :name, provider: "Acme")
    end
  end
end
