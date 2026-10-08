require "test_helper"

class Integrations::Capabilities::NetlifyTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: Integrations::Packs::Netlify::PROVIDER_KEY, name: "Netlify", slug: "netlify")
    @row = integration.integration_environments.create!
    %w[list_deploys describe_site].each do |name|
      integration.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    integration.tools.create!(name: "restore_deploy", description: "Restore", read_only: false, enabled: true, params_schema: { "type" => "object" })
    ResourceMap::Resource.create!(workspace: @workspace, provider: "netlify", account: "acme", kind: ResourceMap::KIND_SITE, external_id: "site-1",
                                  name: "shop", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "a site's deploys and status are its own tools, by its Netlify id" do
    deploys = resolve(Integrations::Capabilities::DEPLOYS, "resource" => "shop", "limit" => 5)
    assert_equal [ "list_deploys", { "site" => "site-1", "limit" => 5 } ], [ deploys.tool.name, deploys.arguments ]

    status = resolve(Integrations::Capabilities::STATUS, "resource" => "shop")
    assert_equal [ "describe_site", { "site" => "site-1" } ], [ status.tool.name, status.arguments ]
  end

  test "a rollback publishes the deploy named, and needs one" do
    rollback = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "shop", "to" => "d1")

    assert_equal [ "restore_deploy", { "site" => "site-1", "deploy" => "d1" } ], [ rollback.tool.name, rollback.arguments ]
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::ROLLBACK, "resource" => "shop") }
  end

  test "Netlify keeps no logs or metrics and runs no instances, so those are not offered for a site" do
    [ Integrations::Capabilities::LOGS, Integrations::Capabilities::METRICS, Integrations::Capabilities::RESTART, Integrations::Capabilities::SCALE ].each do |key|
      assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, "resource" => "shop", "instances" => 1) }
    end
    assert Integrations::Capabilities.wrapped?(Integration::Tool.in_workspace(@workspace).find_by!(name: "restore_deploy"))
  end

  test "run history is a site's deploy history, by its Netlify id, and needs that tool switched on" do
    integration = @workspace.integrations.find_by!(slug: "netlify")
    assert_match "deploy_history tool, which is switched off", assert_raises(Integrations::Capabilities::Unroutable) { resolve(Integrations::Capabilities::HISTORY, "resource" => "shop") }.message

    integration.tools.create!(name: "deploy_history", description: "History", read_only: true, enabled: true, params_schema: { "type" => "object" })
    history = resolve(Integrations::Capabilities::HISTORY, "resource" => "shop", "name" => "production")
    assert_equal [ "deploy_history", { "site" => "site-1", "name" => "production" } ], [ history.tool.name, history.arguments ]
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)
end
