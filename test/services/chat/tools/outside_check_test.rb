require "test_helper"

class Chat::Tools::OutsideCheckTest < ActiveSupport::TestCase
  ANSWER = {
    "url" => "https://shop.example.com/health", "host" => "shop.example.com",
    "dns" => { "records" => [ { "type" => "A", "value" => "203.0.113.7", "ttl" => 60 } ], "ms" => 12 },
    "http" => { "status" => 503, "final_url" => "https://shop.example.com/health", "redirects" => 0, "remote_ip" => "203.0.113.7",
                "timings_ms" => { "dns" => 1, "connect" => 20, "tls" => 45, "first_byte" => 2900, "total" => 2901 } },
    "tls" => { "subject" => "/CN=shop.example.com", "issuer" => "/CN=R11", "not_after" => "2026-10-19T00:00:00Z", "days_left" => 9,
               "names" => [ "shop.example.com" ], "matches_host" => true }
  }.freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                       max_turns: 10, max_spend_cents: 400)
    Integrations::Terminal.stubs(:available?).returns(true)
  end

  test "an address is checked from the sandbox's region, said phase by phase, as a step the ledger holds" do
    Integrations::Terminal.any_instance.expects(:check).with("https://shop.example.com/health", method: "GET")
                          .returns(Integrations::Terminal::Checked.new(answer: ANSWER, region: "europe-west"))

    said = check.call(url: "https://shop.example.com/health")

    assert_includes said, "GET https://shop.example.com/health, checked from the sandbox in europe-west."
    assert_includes said, "DNS (12 ms): A 203.0.113.7 (TTL 60s)."
    assert_includes said, "HTTP: 503 from 203.0.113.7. dns 1 ms, connect 20 ms, tls 45 ms, first byte 2900 ms, total 2901 ms."
    assert_includes said, "expires in 9 days (2026-10-19T00:00:00Z), covers the host. Soon, renew it."
    assert_includes said, "No uptime monitor that checks from several regions is connected."
    step = @investigation.steps.find_by!(action_key: Ability::Action::SANDBOX_COMMAND)
    assert_equal "Check https://shop.example.com/health from outside", step.label
  end

  test "a box with no named region says so, and a connected uptime monitor is named for the other regions" do
    monitor = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "openstatus", name: "OpenStatus",
                                              settings: { "server_url" => "https://api.openstatus.dev/mcp" })
    Integrations::Capabilities.stubs(:outside_checkers).with(@workspace).returns([ monitor ])
    Integrations::Terminal.any_instance.stubs(:check).returns(Integrations::Terminal::Checked.new(answer: ANSWER, region: nil))

    said = check.call(url: "shop.example.com")

    assert_includes said, "checked from the sandbox, in a region this install does not name."
    assert_includes said, "#{monitor.display_name} checks from several regions: resource_status"
  end

  test "only reads are checked, and a check that cannot run says why" do
    Integrations::Terminal.any_instance.expects(:check).never
    assert_match "Only GET or HEAD", check.call(url: "https://x.dev", method: "POST")

    Integrations::Terminal.any_instance.unstub(:check)
    Integrations::Terminal.any_instance.stubs(:check).raises(Integrations::Unavailable, "no provider")
    assert_includes check.call(url: "https://x.dev"), "The check did not run: no provider"
  end

  test "an uptime monitor that checks addresses counts as an outside checker, and a platform does not" do
    openstatus = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "openstatus", name: "OpenStatus",
                                                 settings: { "server_url" => "https://api.openstatus.dev/mcp" })
    openstatus.tools.create!(name: "get_monitor_status", description: "Status", params_schema: {}, enabled: true, read_only: true)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank")
    northflank.tools.create!(name: Integrations::Capabilities.adapter_for("northflank").tool_for(Integrations::Capabilities::STATUS),
                             description: "Status", params_schema: {}, enabled: true, read_only: true)

    assert_equal [ openstatus ], Integrations::Capabilities.outside_checkers(@workspace)
  end

  private

  def check = Chat::Tools::OutsideCheck.new(@investigation)
end
