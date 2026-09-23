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
    datadog = connect!("datadog")

    rows = IntegrationProvider.card_for(@workspace, @telemetry).rows

    assert_equal IntegrationProvider.all.count { |provider| provider.category == "Telemetry" }, rows.size
    assert_equal "datadog", rows.first.provider.key
    assert_equal IntegrationProvider::STATE_CONNECTED, rows.first.state
    assert_equal [ { id: datadog.id, name: "Datadog" } ], rows.first.connections
    assert rows.drop(1).all? { |row| row.state == IntegrationProvider::STATE_NOT_CONNECTED }
  end

  test "a connection whose credentials stopped working needs attention, and one switched off says so" do
    connect!("datadog").integration_environments.sole.record_health!(false, error: "401")
    connect!("grafana").update!(disabled_at: Time.current)

    states = IntegrationProvider.card_for(@workspace, @telemetry).rows.to_h { |row| [ row.provider.key, row.state ] }

    assert_equal IntegrationProvider::STATE_NEEDS_ATTENTION, states["datadog"]
    assert_equal IntegrationProvider::STATE_TURNED_OFF, states["grafana"]
  end

  test "a row says what a person can do from it, so the page and Slack offer the same" do
    connect!("datadog").integration_environments.sole.record_health!(false, error: "401")
    connect!("grafana")

    rows = IntegrationProvider.card_for(@workspace, @telemetry).rows.index_by { |row| row.provider.key }

    assert_equal IntegrationProvider::ACTION_RECONNECT, rows["datadog"].action
    assert_equal IntegrationProvider::ACTION_MANAGE, rows["grafana"].action
    assert_equal IntegrationProvider::ACTION_CONNECT, rows["newrelic"].action
    assert rows["datadog"].opens_connect?
    assert_not rows["grafana"].opens_connect?
  end

  test "a category's key is the same one the agent's tool groups use" do
    assert_equal Chat::Tools::Groups.category_key("Telemetry"), @telemetry.slug
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
