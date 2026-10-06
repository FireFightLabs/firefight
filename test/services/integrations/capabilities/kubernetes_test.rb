require "test_helper"

class Integrations::Capabilities::KubernetesTest < ActiveSupport::TestCase
  CAPABILITIES = Integrations::Capabilities
  TOOLS = %w[workload_logs pod_metrics rollout_history describe_workload rollout_undo rollout_restart scale_workload].freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @kubernetes = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "kubernetes", name: "Kubernetes", slug: "kubernetes")
    @row = @kubernetes.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    TOOLS.each do |name|
      @kubernetes.tools.create!(name: name, description: name, read_only: !name.start_with?("rollout_undo", "rollout_restart", "scale"),
                                enabled: true, params_schema: { "type" => "object" })
    end
    resource!("production/deployment/web", "web", ResourceMap::KIND_SERVICE)
    resource!("production/daemonset/agent", "agent", ResourceMap::KIND_SERVICE)
    resource!("production/cronjob/nightly", "nightly", ResourceMap::KIND_JOB)
    resource!("production/service/web", "web", ResourceMap::KIND_LOAD_BALANCER)
  end

  test "a workload is asked by its namespace and kind/name, with what the request said passed on" do
    logs = resolve(CAPABILITIES::LOGS, "resource" => "web", "text" => "timeout", "minutes" => 30, "stream" => "app")

    assert_equal "kubernetes.workload_logs", logs.tool.action_key
    assert_equal({ "namespace" => "production", "resource" => "deployment/web", "text" => "timeout", "minutes" => 30 }, logs.arguments)
    assert_equal({ "namespace" => "production", "resource" => "cronjob/nightly" }, resolve(CAPABILITIES::STATUS, "resource" => "nightly").arguments)
    assert_equal({ "namespace" => "production", "resource" => "deployment/web", "limit" => 5 }, resolve(CAPABILITIES::DEPLOYS, "resource" => "web", "limit" => 5).arguments)
    assert_match "Kubernetes keeps what a container prints", unroutable(CAPABILITIES::LOGS, "resource" => "web", "stream" => "requests")
    assert_match "no connection offers deploys", unroutable(CAPABILITIES::DEPLOYS, "resource" => "nightly")
  end

  test "metrics are cpu and memory only, and anything else is named as not kept" do
    assert_equal "pod_metrics", resolve(CAPABILITIES::METRICS, "resource" => "web", "metrics" => %w[cpu memory]).tool.name
    assert_match "Kubernetes does not keep http_5xx for this resource. It keeps cpu, memory", unroutable(CAPABILITIES::METRICS, "resource" => "web", "metrics" => [ "http_5xx" ])
  end

  test "a change names a revision or a count, and a daemonset is never scaled" do
    assert_equal({ "namespace" => "production", "resource" => "deployment/web", "revision" => 2 }, resolve(CAPABILITIES::ROLLBACK, "resource" => "web", "to" => "2").arguments)
    assert_match "by the number recent_deploys shows", unroutable(CAPABILITIES::ROLLBACK, "resource" => "web", "to" => "v2")
    assert_equal({ "namespace" => "production", "resource" => "deployment/web", "replicas" => 4 }, resolve(CAPABILITIES::SCALE, "resource" => "web", "instances" => 4).arguments)
    assert_match "cannot be scaled", unroutable(CAPABILITIES::SCALE, "resource" => "agent", "instances" => 2)
    assert_equal "rollout_restart", resolve(CAPABILITIES::RESTART, "resource" => "agent").tool.name
  end

  test "every tool a capability answers whole is not offered again, and logs stay offered for a pod or an earlier container" do
    adapter = Integrations::Capabilities::Kubernetes

    assert_equal %w[pod_metrics rollout_history describe_workload rollout_undo rollout_restart scale_workload], adapter::WRAPPED
    assert_not adapter.wraps?("workload_logs")
    assert_equal TOOLS.sort, adapter::TOOLS.values.sort
    pack_tools = Integrations::Packs::Kubernetes.tool_definitions.map(&:name)
    assert adapter::TOOLS.values.all? { |tool| pack_tools.include?(tool) }
    assert_match "Halon can read its logs, read its metrics, see what was deployed, check how a resource stands, roll a resource back, " \
                 "restart a service, and scale a service for anything Kubernetes runs", Integrations::Capabilities.halon_sentence("kubernetes", "Kubernetes")
  end

  test "an observability tool answers logs for a workload by default, with Kubernetes asked when it has nothing" do
    datadog = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "datadog", name: "Datadog", slug: "datadog",
                                              settings: { "server_url" => "https://mcp.datadoghq.com/api/unstable/mcp-server/mcp" })
    datadog_row = datadog.integration_environments.create!
    datadog.tools.create!(name: "search_datadog_logs", description: "Logs", read_only: true, enabled: true,
                          params_schema: { "type" => "object", "properties" => { "query" => {}, "service" => {}, "from" => {}, "to" => {} } })

    logs = resolve(CAPABILITIES::LOGS, "resource" => "web")

    assert_equal [ datadog_row, @row ], [ logs.environment_row, logs.fallback.environment_row ]
    assert_equal "workload_logs", logs.fallback.tool.name
    assert_equal @row, resolve(CAPABILITIES::STATUS, "resource" => "web").environment_row
  end

  private

  def resource!(id, name, kind)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "kubernetes", account: "cluster.example.com/production", kind: kind, external_id: id,
                                  name: name, integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  def resolve(key, given) = CAPABILITIES.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(CAPABILITIES::Unroutable) { resolve(key, given) }.message
end
