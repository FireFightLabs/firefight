require "test_helper"

class Integrations::Capabilities::FlyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @fly = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly.io", slug: "fly")
    @row = @fly.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    Integrations::Packs::Fly.tool_definitions.each do |definition|
      @fly.tools.create!(name: definition.name, description: definition.name, read_only: definition.read_only, enabled: true, params_schema: definition.params_schema)
    end
    resource!(ResourceMap::KIND_SERVICE, "web")
    resource!(ResourceMap::KIND_DATABASE, "pg1", name: "main-db")
  end

  test "an app's logs, metrics, releases and status are its own tools' calls, by its name" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "exclude" => "health", "minutes" => 30)
    assert_equal [ "fly.search_logs", { "resource" => "web", "text" => "timeout", "exclude" => "health", "minutes" => 30 } ], [ logs.tool.action_key, logs.arguments ]

    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu http_5xx])
    assert_equal({ "resource" => "web", "metrics" => %w[cpu http_5xx] }, metrics.arguments)
    assert_equal "list_deployments", resolve(Integrations::Capabilities::DEPLOYS, "resource" => "web").tool.name
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS, "resource" => "main-db").tool.name
  end

  test "a rollback and a restart go to the change tools, and what Fly does not keep or offer is refused in words" do
    assert_equal [ "rollback_release", { "resource" => "web", "release" => "41" } ],
                 resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "41").then { |call| [ call.tool.name, call.arguments ] }
    assert_equal "restart_app", resolve(Integrations::Capabilities::RESTART, "resource" => "web").tool.name

    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "build")
    assert_match "Fly.io does not keep disk", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "disk" ])
    assert_match "no connection offers scaling", unroutable(Integrations::Capabilities::SCALE, "resource" => "web", "instances" => 2)
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "main-db")
  end

  test "every tool the adapter runs is one the pack declares, every metric is in the shared vocabulary, and the wrapped ones are not offered twice" do
    declared = Integrations::Packs::Fly.tool_definitions.map(&:name)

    assert_empty Integrations::Capabilities::Fly::TOOLS.values - declared
    assert_empty Integrations::Packs::Fly::METRICS.keys - Integrations::Capabilities::METRIC_NAMES
    assert Integrations::Capabilities.wrapped?(@fly.tools.find_by!(name: "rollback_release"))
    assert_equal %w[logs metrics deploys status rollback restart], Integrations::Capabilities::Fly.capabilities
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message

  def resource!(kind, id, name: id)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "fly", account: "acme", kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
