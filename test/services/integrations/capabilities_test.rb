require "test_helper"

class Integrations::CapabilitiesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @northflank, @northflank_row = connect("northflank", "Northflank", %w[search_logs query_metrics list_deployments describe_resource api_request])
    @web = resource!(@northflank_row, "northflank", ResourceMap::KIND_SERVICE, "web-id", "web")
  end

  test "a resource is found by its name on the map and answered by the connection that holds it, as that provider's own call" do
    call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "text" => "timeout", "stream" => "requests")

    assert_equal "northflank.search_logs", call.tool.action_key
    assert_equal({ "resource" => "web-id", "type" => "ingress", "text" => "timeout" }, call.arguments)
    assert_equal @northflank_row, call.environment_row
  end

  test "nothing of that name, nothing that can answer, and a switched off tool each say what to do" do
    assert_match "Nothing on the resource map is called checkout",
                 assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "checkout") }.message

    resource!(@northflank_row, "northflank", ResourceMap::KIND_JOB, "nightly-id", "nightly")
    assert_match "no connection that holds it offers deploys",
                 assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::DEPLOYS, "resource" => "nightly") }.message

    @northflank.tools.find_by!(name: "list_deployments").update!(enabled: false)
    assert_match "list_deployments tool, which is switched off",
                 assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::DEPLOYS, "resource" => "web") }.message
  end

  test "a resource two connections hold asks which one, and the choice picks it" do
    _second, second_row = connect("northflank", "Northflank staging", %w[search_logs], slug: "northflank_staging", entry: catalog_entries(:development_env))
    resource!(second_row, "northflank", ResourceMap::KIND_SERVICE, "web-staging", "web", account: "team/staging")

    error = assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "web") }
    assert_match "choose connection from: northflank, northflank_staging", error.message

    call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "connection" => "northflank_staging")
    assert_equal "web-staging", call.arguments["resource"]
  end

  test "a hostname is answered by what serves it" do
    host = ResourceMap::Resource.create!(workspace: @workspace, provider: "dns", account: "dns", kind: ResourceMap::KIND_DOMAIN, external_id: "app.example.com",
                                         name: "app.example.com", first_seen_at: Time.current, last_seen_at: Time.current)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: host, to_resource: @web, relation: ResourceMap::RELATION_SERVED_BY,
                              integration_environment: @northflank_row, origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)

    assert_equal "web-id", Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, "resource" => "app.example.com").arguments["resource"]
  end

  test "Northflank maps metrics to its own names, refuses one it does not keep, and makes a change through its API" do
    metrics = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => %w[http_5xx disk], "minutes" => 30)
    assert_equal({ "resource" => "web-id", "metrics" => %w[http5xxResponses diskUsage], "minutes" => 30 }, metrics.arguments)
    assert_match "Northflank does not keep cpu_time",
                 assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::METRICS, "resource" => "web", "metrics" => [ "cpu_time" ]) }.message

    builder = resource!(@northflank_row, "northflank", ResourceMap::KIND_BUILD_SERVICE, "builder-id", "builder")
    ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: builder, relation: ResourceMap::RELATION_RUNS_BUILDS_OF,
                              integration_environment: @northflank_row, origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
    rollback = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::ROLLBACK, "resource" => "web", "to" => "build-7")
    assert_equal({ "method" => "POST", "path" => "services/web-id/deployment", "body" => { "internal" => { "id" => "builder-id", "buildId" => "build-7" } } },
                 rollback.arguments)
    assert_equal({ "method" => "POST", "path" => "services/web-id/scale", "body" => { "instances" => 3 } },
                 Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::SCALE, "resource" => "web", "instances" => "3").arguments)
    assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::SCALE, "resource" => "web", "instances" => "lots") }
  end

  test "the capabilities offered are the ones a connected provider's switched on tools can answer, and their duplicates are known" do
    offered = Integrations::Capabilities.offered(@workspace).to_h { |spec, tools| [ spec.tool_name, tools.map(&:name) ] }

    assert_equal %w[search_logs query_metrics recent_deploys resource_status rollback restart scale], offered.keys
    assert_equal [ "api_request" ], offered["rollback"]
    assert Integrations::Capabilities.wrapped?(@northflank.tools.find_by!(name: "search_logs"))
    assert_not Integrations::Capabilities.wrapped?(@northflank.tools.find_by!(name: "api_request"))
  end

  test "two resources of one name are told apart by id, never picked for the agent" do
    resource!(@northflank_row, "northflank", ResourceMap::KIND_DATABASE, "web-db-id", "web")

    error = assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, "resource" => "web") }
    assert_match "More than one resource is called web", error.message
    assert_equal "web-db-id", Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, "resource" => "web-db-id").arguments["resource"]
  end

  test "a connection wired to two environments is chosen with its environment" do
    staging_row = @northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:development_env).id, credentials: { token: "y" }.to_json)
    @web.update!(sightings: { staging_row.id.to_s => {} })

    error = assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "web") }
    labels = [ "northflank/#{catalog_entries(:production_env).slug}", "northflank/#{catalog_entries(:development_env).slug}" ]
    assert_match "Choose connection from: #{labels.join(', ')}", error.message
    call = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "web", "connection" => labels.last)
    assert_equal staging_row, call.environment_row
  end

  test "a resource reaches only enabled connections of its own workspace" do
    @northflank.update!(disabled_at: Time.current)
    assert_match "no connection that holds it",
                 assert_raises(Integrations::Capabilities::Unroutable) { Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "web") }.message

    other = workspaces(:slack_workspace_two).integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Theirs", slug: "theirs")
    @web.update!(integration_environment: other.integration_environments.create!(credentials: { token: "z" }.to_json))
    assert_empty @web.reload.holders
  end

  test "a build service's logs are its builds' unless asked otherwise" do
    resource!(@northflank_row, "northflank", ResourceMap::KIND_BUILD_SERVICE, "builder-id", "builder")

    assert_equal "build", Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::LOGS, "resource" => "builder").arguments["type"]
  end

  test "a provider's details say what Halon can do through it, in the capabilities' order, and one with no adapter is used through its tools" do
    assert_equal "Halon can read its logs, read its metrics, see what was deployed, check how a resource stands, and roll a resource back " \
                 "for anything Cloudflare runs. It also uses Cloudflare's own tools that you switch on.", Integrations::Capabilities.halon_sentence("cloudflare", "Cloudflare")
    assert_equal "Halon uses Datadog's own tools that you switch on, in chats and investigations.", Integrations::Capabilities.halon_sentence("datadog", "Datadog")
    details = IntegrationProviderSerializer.one(IntegrationProvider.find("cloudflare"))
    assert details[:onMap]
    assert_not IntegrationProviderSerializer.one(IntegrationProvider.find("datadog"))[:onMap]
  end

  private

  def connect(provider, name, tools, slug: nil, entry: catalog_entries(:production_env))
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name, slug: slug || provider)
    row = integration.integration_environments.create!(catalog_entry_id: entry.id, credentials: { token: "x" }.to_json)
    tools.each { |tool| integration.tools.create!(name: tool, description: tool, read_only: tool != "api_request", enabled: true, params_schema: { "type" => "object" }) }
    [ integration, row ]
  end

  def resource!(row, provider, kind, id, name, account: "team/prod")
    ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: account, kind: kind, external_id: id, name: name,
                                  integration_environment: row, first_seen_at: Time.current, last_seen_at: Time.current)
  end
end
