require "test_helper"

class Integrations::Capabilities::BetterstackTest < ActiveSupport::TestCase
  include ObserverTestHelper

  setup do
    run_web_on_northflank
    serve_hostname("shop.acme.com")
    monitors = [ { "id" => "175", "name" => "Shop", "url" => "https://shop.acme.com" }, { "id" => "180", "name" => "Shop API", "url" => "https://shop.acme.com/api" } ]
    @row = watch_with("betterstack", "Better Stack", { "monitor" => %w[monitor_id] }, learned: { "monitors" => monitors })
  end

  test "Better Stack answers how a hostname stands from the monitor that checks it, naming the others" do
    status = resolve(Integrations::Capabilities::STATUS, "resource" => "shop.acme.com", "connection" => "betterstack")

    assert_equal [ @row, "monitor", { "monitor_id" => "175" } ], [ status.environment_row, status.tool.name, status.arguments ]
    assert_equal "Other Better Stack monitors on the same hostname: Shop API (180).", status.present_result(answer("up"))["content"].last["text"]
  end

  test "a monitor tool whose id argument is unknown is refused in words" do
    @row.integration.tools.find_by!(name: "monitor").update!(params_schema: { "type" => "object", "properties" => { "name" => {} } })

    assert_match "takes its monitor in a way Firefight does not know", unroutable(Integrations::Capabilities::STATUS, "resource" => "shop.acme.com", "connection" => "betterstack")
  end
end
