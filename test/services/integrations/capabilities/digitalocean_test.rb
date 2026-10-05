require "test_helper"

class Integrations::Capabilities::DigitaloceanTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: Integrations::Packs::Digitalocean::PROVIDER_KEY,
                                                  name: "DigitalOcean", slug: "digitalocean")
    @row = integration.integration_environments.create!(credentials: { api_token: "x" }.to_json)
    Integrations::Packs::Digitalocean.tool_definitions.each do |definition|
      integration.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                                params_schema: definition.params_schema)
    end
    { "app-1" => [ ResourceMap::KIND_SERVICE, "shop" ], "3164494" => [ ResourceMap::KIND_VIRTUAL_MACHINE, "bastion" ],
      "db-1" => [ ResourceMap::KIND_DATABASE, "shop-db" ] }.each do |id, (kind, name)|
      ResourceMap::Resource.create!(workspace: @workspace, provider: Integrations::Packs::Digitalocean::PROVIDER_KEY, account: "Acme", kind: kind,
                                    external_id: id, name: name, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    end
  end

  test "an app's logs, deploys, status and changes run as DigitalOcean's own tools by its id" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "shop", "text" => "timeout", "minutes" => 30)
    assert_equal [ "app_logs", { "resource" => "app-1", "type" => "RUN", "text" => "timeout", "minutes" => 30 } ], [ logs.tool.name, logs.arguments ]
    assert_equal "BUILD", resolve(Integrations::Capabilities::LOGS, "resource" => "shop", "stream" => "build").arguments["type"]
    assert_equal "list_deployments", resolve(Integrations::Capabilities::DEPLOYS, "resource" => "shop").tool.name
    assert_equal({ "resource" => "app-1", "deployment" => "dep-1" }, resolve(Integrations::Capabilities::ROLLBACK, "resource" => "shop", "to" => "dep-1").arguments)
    assert_equal [ "restart_app", { "resource" => "app-1" } ], resolve(Integrations::Capabilities::RESTART, "resource" => "shop").then { |call| [ call.tool.name, call.arguments ] }
    assert_equal({ "resource" => "app-1", "instances" => 3 }, resolve(Integrations::Capabilities::SCALE, "resource" => "shop", "instances" => 3).arguments)
  end

  test "a Droplet answers metrics, status and a restart by rebooting, and a database metrics and status" do
    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "bastion", "metrics" => %w[cpu disk network_in], "minutes" => 120)
    assert_equal [ "resource_metrics", { "resource" => "3164494", "metrics" => %w[cpu disk network_in], "minutes" => 120 } ], [ metrics.tool.name, metrics.arguments ]
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS, "resource" => "shop-db").tool.name
    assert_equal [ "reboot_droplet", { "resource" => "3164494" } ], resolve(Integrations::Capabilities::RESTART, "resource" => "bastion").then { |call| [ call.tool.name, call.arguments ] }
    assert_match "no connection offers a restart", unroutable(Integrations::Capabilities::RESTART, "resource" => "shop-db")
    assert_match "no connection offers logs", unroutable(Integrations::Capabilities::LOGS, "resource" => "shop-db")
  end

  test "what DigitalOcean does not keep is refused with words" do
    assert_match "stream must be one of those", unroutable(Integrations::Capabilities::LOGS, "resource" => "shop", "stream" => "requests")
    assert_match "does not keep http_5xx", unroutable(Integrations::Capabilities::METRICS, "resource" => "shop", "metrics" => [ "http_5xx" ])
    assert_match "1 or more", unroutable(Integrations::Capabilities::SCALE, "resource" => "shop", "instances" => 0)
    assert_match "Say what to roll back to", unroutable(Integrations::Capabilities::ROLLBACK, "resource" => "shop")
  end

  test "Halon is offered the tools that take more than their capability, and not the ones a capability answers in full" do
    wrapped = Integration::Tool.in_workspace(@workspace).select { |tool| Integrations::Capabilities.wrapped?(tool) }.map(&:name).sort

    assert_equal %w[describe_resource list_deployments reboot_droplet rollback_app], wrapped
    assert_match "roll a resource back", Integrations::Capabilities.halon_sentence(Integrations::Packs::Digitalocean::PROVIDER_KEY, "DigitalOcean")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
