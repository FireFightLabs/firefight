# A workspace where Northflank runs a service called web and a provider under test watches it, as in an observability
# adapter's tests.
module ObserverTestHelper
  def run_web_on_northflank
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @northflank_row = northflank.integration_environments.create!(credentials: { token: "x" }.to_json)
    %w[search_logs query_metrics describe_resource].each do |name|
      northflank.tools.create!(name: name, description: name, read_only: true, enabled: true, params_schema: { "type" => "object" })
    end
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE,
                                         external_id: "web-id", name: "web", integration_environment: @northflank_row,
                                         first_seen_at: Time.current, last_seen_at: Time.current)
  end

  # A connection to the provider's own server with the tools named, each taking the parameters listed, switched on,
  # with what the connect form asked (fields) and what its health check learned (learned).
  def watch_with(provider, name, tools, fields: {}, learned: {})
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: name, slug: provider,
                                                  settings: { "server_url" => IntegrationProvider.find(provider).server_url })
    row = integration.integration_environments.create!(base_config: { IntegrationEnvironment::FIELDS_KEY => fields, IntegrationEnvironment::LEARNED_KEY => learned })
    tools.each do |tool, parameters|
      integration.tools.create!(name: tool, description: tool, read_only: true, enabled: true,
                                params_schema: { "type" => "object", "properties" => parameters.index_with { {} } })
    end
    row
  end

  # A hostname on the map that the web service serves.
  def serve_hostname(host)
    domain = ResourceMap::Resource.create!(workspace: @workspace, provider: ResourceMap::DOMAINS, account: host.split(".").last(2).join("."),
                                           kind: ResourceMap::KIND_DOMAIN, external_id: host, name: host, integration_environment: @northflank_row,
                                           first_seen_at: Time.current, last_seen_at: Time.current)
    ResourceMap::Link.create!(workspace: @workspace, from_resource: domain, to_resource: @web, relation: ResourceMap::RELATION_SERVED_BY,
                              origin: ResourceMap::ORIGIN_DECLARED, integration_environment: @northflank_row, last_seen_at: Time.current)
    domain
  end

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message

  def answer(text) = { "content" => [ { "type" => "text", "text" => text.is_a?(String) ? text : text.to_json } ] }
end
