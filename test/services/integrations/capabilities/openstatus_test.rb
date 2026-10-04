require "test_helper"

class Integrations::Capabilities::OpenstatusTest < ActiveSupport::TestCase
  include ObserverTestHelper

  setup do
    run_web_on_northflank
    serve_hostname("shop.acme.com")
    monitors = [ { "id" => 7, "name" => "Shop", "url" => "https://shop.acme.com/health" }, { "id" => 3, "name" => "Shop home", "url" => "https://shop.acme.com" },
                 { "id" => 9, "name" => "Docs", "url" => "https://docs.acme.com" } ]
    @row = watch_with("openstatus", "OpenStatus", { "get_monitor_status" => %w[monitorId] }, learned: { "monitors" => monitors })
  end

  test "OpenStatus answers how a hostname stands from the monitor that checks it, region by region" do
    status = resolve(Integrations::Capabilities::STATUS, "resource" => "shop.acme.com", "connection" => "openstatus")

    assert_equal [ @row, "get_monitor_status", { "monitorId" => 3 } ], [ status.environment_row, status.tool.name, status.arguments ]
    body = { "monitorId" => 3, "regions" => [ { "region" => "ams", "status" => "active" }, { "region" => "iad", "status" => "error" } ] }
    text = status.present_result(answer(body))["content"].first["text"]
    assert_match "OpenStatus monitor Shop home (https://shop.acme.com) is error in 1 of 2 regions", text
    assert_match "Other monitors on the same hostname: Shop (7).", text
  end

  test "the service a hostname serves is the platform's to describe, and OpenStatus answers for it when named" do
    assert_equal @northflank_row, resolve(Integrations::Capabilities::STATUS, "resource" => "web").environment_row
    assert_equal @row, resolve(Integrations::Capabilities::STATUS, "resource" => "web", "connection" => "openstatus").environment_row
  end

  test "a hostname no platform describes is answered by OpenStatus by default, and one no monitor checks is said" do
    %w[docs.acme.com api.acme.com].each do |host|
      ResourceMap::Resource.create!(workspace: @workspace, provider: ResourceMap::DOMAINS, account: "acme.com", kind: ResourceMap::KIND_DOMAIN,
                                    external_id: host, name: host, first_seen_at: Time.current, last_seen_at: Time.current)
    end

    assert_equal [ @row, { "monitorId" => 9 } ], resolve(Integrations::Capabilities::STATUS, "resource" => "docs.acme.com").then { |call| [ call.environment_row, call.arguments ] }
    assert_match "No OpenStatus monitor checks api.acme.com", unroutable(Integrations::Capabilities::STATUS, "resource" => "api.acme.com")

    @row.update!(base_config: {})
    assert_match "no connection offers status", unroutable(Integrations::Capabilities::STATUS, "resource" => "docs.acme.com")
  end
end
