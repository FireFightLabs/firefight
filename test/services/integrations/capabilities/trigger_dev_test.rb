require "test_helper"

class Integrations::Capabilities::TriggerDevTest < ActiveSupport::TestCase
  PACK = Integrations::Packs::TriggerDev

  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: PACK::PROVIDER_KEY, name: "Trigger.dev", slug: "trigger")
    @row = integration.integration_environments.create!(credentials: { PACK::API_KEY => "tr_prod_sk_x", PACK::PROJECT => "proj_acme" }.to_json)
    Integrations::Capabilities::TriggerDev::TOOLS.values.each do |name|
      integration.tools.create!(name: name, description: name, read_only: name != "promote_deployment", enabled: true, params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: PACK::PROVIDER_KEY, account: "proj_acme", kind: ResourceMap::KIND_JOB,
                                  external_id: "send-email", name: "send-email", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "a task's logs, errors, status and metrics run as the pack's own tools, by the task's identifier" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "send-email", "text" => "timeout", "minutes" => 30)
    assert_equal [ @row, "search_task_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal({ "task" => "send-email", "text" => "timeout", "minutes" => 30 }, logs.arguments)

    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "send-email", "text" => "smtp")
    assert_equal [ "list_errors", { "task" => "send-email", "text" => "smtp" } ], [ errors.tool.name, errors.arguments ]
    assert_equal({ "task" => "send-email" }, resolve(Integrations::Capabilities::STATUS, "resource" => "send-email").arguments)

    metrics = resolve(Integrations::Capabilities::METRICS, "resource" => "send-email", "metrics" => %w[requests errors cpu])
    assert_equal({ "task" => "send-email", "metrics" => %w[requests errors cpu] }, metrics.arguments)
  end

  test "deploys and a rollback are the environment's, and a rollback takes the version to promote" do
    assert_equal({ "limit" => 5 }, resolve(Integrations::Capabilities::DEPLOYS, "resource" => "send-email", "limit" => 5).arguments)

    rollback = resolve(Integrations::Capabilities::ROLLBACK, "resource" => "send-email", "to" => "20261001.1")
    assert_equal [ "promote_deployment", { "version" => "20261001.1" } ], [ rollback.tool.name, rollback.arguments ]
    assert_match "Say what to roll back to", unroutable(Integrations::Capabilities::ROLLBACK, "resource" => "send-email")
  end

  test "what Trigger.dev does not keep is refused in words, and restarts and scaling are not offered" do
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "send-email", "stream" => "build")
    assert_match "does not keep http_5xx", unroutable(Integrations::Capabilities::METRICS, "resource" => "send-email", "metrics" => [ "http_5xx" ])
    assert_match "no connection offers a restart", unroutable(Integrations::Capabilities::RESTART, "resource" => "send-email")
    assert_match "no connection offers scaling", unroutable(Integrations::Capabilities::SCALE, "resource" => "send-email", "instances" => 2)
  end

  test "the tools a capability answers are not offered to Halon twice, and the rest stay" do
    adapter = Integrations::Capabilities::TriggerDev

    assert adapter.wraps?("search_task_logs")
    assert adapter.wraps?("promote_deployment")
    assert_not adapter.wraps?("list_runs")
    assert_not adapter.wraps?("run_details")
    assert_match "roll a resource back", Integrations::Capabilities.halon_sentence(PACK::PROVIDER_KEY, PACK::PROVIDER)
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given)
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
  end
end
