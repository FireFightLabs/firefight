require "test_helper"

class IntegrationProviderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @telemetry = IntegrationProvider.category_for!("telemetry")
  end

  test "a category is found by its slug or its name, whatever the case" do
    assert_equal "Telemetry", IntegrationProvider.category_for!("Telemetry").name
    assert_equal @telemetry, IntegrationProvider.category_for!("TELEMETRY")
  end

  test "a category that does not exist is refused with the ones that do" do
    error = assert_raises(ArgumentError) { IntegrationProvider.category_for!("monitoring") }

    assert_match "telemetry (Telemetry)", error.message
  end

  test "a card holds every provider in the category, connected ones first" do
    connect!("datadog")

    rows = IntegrationProvider.card_for(@workspace, @telemetry).rows

    assert_equal IntegrationProvider.all.count { |provider| provider.category == "Telemetry" }, rows.size
    assert_equal "datadog", rows.first.provider.key
    assert_equal IntegrationProvider::STATE_CONNECTED, rows.first.state
    assert_equal [ "Datadog" ], rows.first.connections
    assert rows.drop(1).all? { |row| row.state == IntegrationProvider::STATE_NOT_CONNECTED }
  end

  test "a connection whose credentials stopped working needs attention, and one switched off says so" do
    connect!("datadog").integration_environments.sole.record_health!(false, error: "401")
    connect!("grafana").update!(disabled_at: Time.current)

    states = IntegrationProvider.card_for(@workspace, @telemetry).rows.to_h { |row| [ row.provider.key, row.state ] }

    assert_equal IntegrationProvider::STATE_NEEDS_ATTENTION, states["datadog"]
    assert_equal IntegrationProvider::STATE_TURNED_OFF, states["grafana"]
  end

  test "a connection that was removed counts as never connected" do
    connect!("datadog").update!(deleted_at: Time.current)

    row = IntegrationProvider.card_for(@workspace, @telemetry).rows.find { |candidate| candidate.provider.key == "datadog" }

    assert_equal IntegrationProvider::STATE_NOT_CONNECTED, row.state
  end

  private

  def connect!(key)
    provider = IntegrationProvider.find(key)
    integration = @workspace.integrations.create!(
      kind: provider.kind, provider: key, name: provider.name, settings: { "server_url" => "https://#{key}.example/mcp" }
    )
    integration.integration_environments.create!
    integration
  end
end
