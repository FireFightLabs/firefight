require "test_helper"

class IntegrationProviderTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @telemetry = IntegrationProvider.category_for!("observability")
  end

  test "a category is found by its slug or its name, whatever the case" do
    assert_equal "Observability", IntegrationProvider.category_for!("Observability").name
    assert_equal @telemetry, IntegrationProvider.category_for!("OBSERVABILITY")
  end

  test "a category that does not exist is refused with the ones that do" do
    error = assert_raises(ArgumentError) { IntegrationProvider.category_for!("monitoring") }

    assert_match "observability (Observability)", error.message
  end

  test "a card holds every provider in the category, connected ones first" do
    datadog = connect!("datadog")

    rows = IntegrationProvider.card_for(@workspace, @telemetry).rows

    assert_equal IntegrationProvider.all.count { |provider| provider.category == "Observability" }, rows.size
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
    assert_equal Chat::Tools::Groups.category_key("Observability"), @telemetry.slug
  end

  test "a connection that was removed counts as never connected" do
    connect!("datadog").update!(deleted_at: Time.current)

    row = IntegrationProvider.card_for(@workspace, @telemetry).rows.find { |candidate| candidate.provider.key == "datadog" }

    assert_equal IntegrationProvider::STATE_NOT_CONNECTED, row.state
  end

  test "a coding agent is a native pack whose tool writes the change, chosen apart from the code hosts" do
    assert_equal %w[devin cursor factory], IntegrationProvider.coding_agents.map(&:key)
    assert_equal %w[github], IntegrationProvider.code_hosts.map(&:key)
    IntegrationProvider.coding_agents.each do |provider|
      definitions = Integrations::NativePack.for(provider.key).tool_definitions.index_by(&:name)
      assert_equal [ Integration::KIND_NATIVE, IntegrationProvider::CONNECT_API_TOKEN ], [ provider.kind, provider.connect_with ]
      assert_not definitions.fetch(provider.code_fix_tool).read_only, "#{provider.key}'s #{provider.code_fix_tool} changes code"
      assert_equal "Coding agents", provider.category
    end
  end

  test "only a provider connected with credentials that has its own MCP server can connect through it, and only when asked" do
    gitlab = IntegrationProvider.find("gitlab")

    assert gitlab.mcp_alternative?
    assert_equal [ Integration::KIND_MCP, Integration::KIND_NATIVE ], [ gitlab.connect_kind(Integration::KIND_MCP), gitlab.connect_kind(nil) ]
    assert_not IntegrationProvider.find("northflank").mcp_alternative?, "Northflank has no server of its own"
    assert_equal Integration::KIND_NATIVE, IntegrationProvider.find("github").connect_kind(Integration::KIND_MCP)
    assert_equal Integration::KIND_MCP, IntegrationProvider.find("circleci").connect_kind(nil)
  end

  test "CI is a group of its own, after Code" do
    names = IntegrationProvider.category_list.map(&:name)

    assert_equal names.index("Code") + 1, names.index("CI")
    assert_equal "ci", IntegrationProvider.category_slug(IntegrationProvider.find("circleci").category)
  end

  test "every category says what Halon does with it, and setup requires code, hosting and observability" do
    IntegrationProvider.category_list.each do |category|
      assert category.halon.present?, "#{category.name} says what Halon can do with it"
      assert_no_match(/[—;]/, category.halon, "#{category.name}'s sentence is user copy")
    end

    assert_equal [ "Cloud and hosting", "Observability", "Code" ], IntegrationProvider.category_list.select(&:required).map(&:name)
    assert_equal [ "Cloud and hosting", "Databases" ], IntegrationProvider.category_list.select(&:in_first_question).map(&:name)
    assert_equal IntegrationProvider.category_list.to_h { |category| [ category.name, category.tagline ] }, IntegrationProvider.categories
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
