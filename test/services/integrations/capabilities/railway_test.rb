require "test_helper"

class Integrations::Capabilities::RailwayTest < ActiveSupport::TestCase
  TOOLS = %w[search_logs query_metrics list_deployments describe_resource rollback_deployment restart_deployment scale_service].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @railway = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway", slug: "railway")
    @row = @railway.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    TOOLS.each do |tool|
      @railway.tools.create!(name: tool, description: tool, read_only: !tool.match?(/rollback|restart|scale/), enabled: true, params_schema: { "type" => "object" })
    end
    resource!("svc-web", "web", ResourceMap::KIND_SERVICE)
    resource!("svc-db", "Postgres", ResourceMap::KIND_DATABASE)
  end

  test "a resource on the map is answered by Railway's own tools, by its service id, with Railway's names for streams" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "requests", "text" => "timeout", "exclude" => "healthz", "minutes" => 30)

    assert_equal "railway.search_logs", logs.tool.action_key
    assert_equal({ "resource" => "svc-web", "type" => "http", "text" => "timeout", "exclude" => "healthz", "minutes" => 30 }, logs.arguments)
    assert_equal({ "resource" => "svc-web", "metrics" => %w[cpu http_5xx] },
                 resolve(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[cpu http_5xx]).arguments)
    assert_equal({ "resource" => "svc-db" }, resolve(Integrations::Capabilities::STATUS, "resource" => "Postgres").arguments)
  end

  test "what Railway cannot search or does not keep is refused in words" do
    assert_match "no regular expressions", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "regex" => "5\\d\\d")
    assert_match "stream must be app, build, requests", unroutable(Integrations::Capabilities::LOGS, "resource" => "web", "stream" => "cdn")
    assert_match "Railway does not keep tcp_connections", unroutable(Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "tcp_connections" ])
    assert_match "no connection offers scaling", unroutable(Integrations::Capabilities::SCALE, "resource" => "Postgres", "instances" => 2)
  end

  test "a rollback, restart and scale run as Railway's change tools" do
    assert_equal({ "resource" => "svc-web", "deployment" => "dep-1" }, resolve(Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "dep-1").arguments)
    assert_equal "restart_deployment", resolve(Integrations::Capabilities::RESTART, "resource" => "Postgres").tool.name
    assert_equal({ "resource" => "svc-web", "instances" => 3 }, resolve(Integrations::Capabilities::SCALE, "resource" => "web", "instances" => "3").arguments)
  end

  test "Railway's wrapped tools are not offered twice, and its details say what Halon can do" do
    assert Integrations::Capabilities.wrapped?(@railway.tools.find_by!(name: "scale_service"))
    assert_equal %w[logs metrics deploys status rollback restart scale], Integrations::Capabilities::Railway.capabilities
    assert_match "for anything Railway runs", Integrations::Capabilities.halon_sentence("railway", "Railway")
  end

  private

  def resource!(id, name, kind)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "railway", account: "prj-1/env-prod", kind: kind, external_id: id, name: name,
                                  integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
