require "test_helper"

# Railway's, PlanetScale's and Supabase's changes from setup to the map. Firefight registers Railway's webhook itself and
# checks the header it gave it. PlanetScale and Supabase are reached through their MCP servers, so an admin adds the
# webhook and saves its secret, and the scope a delivery names is read again through the connection's switched on tools.
class LiveUpdatesRailwayPlanetscaleSupabaseTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "Railway: a delivery with Firefight's header re-reads the service it names, one without is refused, and a deleted service goes" do
    row = railway_row
    Integrations::RailwayApi.any_instance.stubs(:notification_rules).returns([])
    Integrations::RailwayApi.any_instance.expects(:create_webhook).with("ws-1", "prj-1", has_entries(events: Integrations::MapEventSources::Railway::EVENTS))
                            .returns("id" => "rule-1")
    with_app_host { Integrations::MapEvents.prepare!(row) }
    row.reload
    assert_equal [ "rule-1", true ], [ row.map_events_webhook_id, row.live_updates.on ]
    secret = row.map_events_secret
    assert_equal 64, secret.size

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ railway_service("svc-web", "SUCCESS"), railway_service("svc-old", "SUCCESS") ]))
    Integrations::RailwayApi.any_instance.stubs(:service_instance).with("env-prod", "svc-web")
                            .returns("serviceId" => "svc-web", "serviceName" => "web", "latestDeployment" => { "id" => "dep-2", "status" => "CRASHED" })
    Integrations::RailwayApi.any_instance.stubs(:service_variables).returns([ {}, {} ])

    body = railway_delivery("Deployment.crashed", "svc-web")
    post api_v1_map_events_path(row.map_events_token), params: body, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: body, headers: railway_headers("not-it")
    assert_response :unauthorized
    assert_not ResourceMap::ReceivedEvent.exists?(integration_environment: row)

    2.times do
      post api_v1_map_events_path(row.map_events_token), params: body, headers: railway_headers(secret)
      assert_response :ok
    end
    assert_equal 1, ResourceMap::ReceivedEvent.where(integration_environment: row).count, "a retry of the same body is kept once"

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "crashed", map_resource("railway", "svc-web").status

    Integrations::RailwayApi.any_instance.stubs(:service_instance).with("env-prod", "svc-old")
                            .raises(Integrations::RailwayApi::NotFound, "Railway refused this: ServiceInstance not found")
    post api_v1_map_events_path(row.map_events_token), params: railway_delivery("Deployment.removed", "svc-old"), headers: railway_headers(secret)
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert map_resource("railway", "svc-old").removed_at.present?

    Integrations::RailwayApi.any_instance.expects(:delete_webhook).with("rule-1").returns(true)
    Integrations::MapEvents.connection_removed(row.integration)
    assert_nil row.reload.map_events_webhook_id
  end

  test "Railway: a token that may not add webhooks leaves live updates off with Railway's words, tried again tomorrow" do
    row = railway_row
    Integrations::RailwayApi.any_instance.stubs(:notification_rules).returns([])
    Integrations::RailwayApi.any_instance.stubs(:create_webhook).raises(Integrations::RailwayApi::Refused, "Railway refused this: Not Authorized")
    with_app_host { Integrations::MapEvents.prepare!(row) }

    state = row.reload.live_updates
    assert_not state.on
    assert_equal "Firefight could not follow Railway's changes: Railway refused this: Not Authorized. Firefight tries again tomorrow. " \
                 "The map still updates at each sweep.", state.reason
  end

  test "PlanetScale: each database's secret is added, a delivery signed with any of them re-reads the branch it names through the tools" do
    row = mcp_row("planetscale", "PlanetScale", "https://mcp.pscale.dev/mcp/planetscale",
                  %w[planetscale_get_database planetscale_get_branch planetscale_list_branches])
    sign_in_admin
    assert_equal "Send PlanetScale's changes to Firefight and save the signing secret under Integrations to turn them on.", row.live_updates.reason

    patch map_events_secret_integration_path(row.integration), params: { environment_row_id: row.id, secret: "first-database-secret" }
    patch map_events_secret_integration_path(row.integration), params: { environment_row_id: row.id, secret: "second-database-secret" }
    assert_equal "Signing secret added. PlanetScale now has 2 signing secrets saved, and a change signed with any one reaches the map.", flash[:notice]
    assert_equal %w[first-database-secret second-database-secret], row.reload.map_events_secrets
    assert row.live_updates.on

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "planetscale", account: "acme", kind: ResourceMap::KIND_BRANCH, external_id: "shop/dev", name: "shop/dev", status: "ready")
    ]))
    Integrations::McpClient.any_instance.stubs(:call_tool).with(name: "planetscale_get_database", arguments: anything)
                           .returns(text_result("name" => "shop", "state" => "ready", "kind" => "mysql"))
    Integrations::McpClient.any_instance.stubs(:call_tool).with(name: "planetscale_get_branch", arguments: anything)
                           .returns(text_result("name" => "dev", "state" => "sleeping", "production" => false))

    body = { "timestamp" => Time.current.to_i, "event" => "branch.sleeping", "organization" => "acme", "database" => "shop",
             "resource" => { "name" => "dev", "state" => "sleeping" } }.to_json
    post api_v1_map_events_path(row.map_events_token), params: body,
                                                       headers: { "X-PlanetScale-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "unknown", body), "Content-Type" => "application/json" }
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: body,
                                                       headers: { "X-PlanetScale-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "second-database-secret", body), "Content-Type" => "application/json" }
    assert_response :ok

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "sleeping", map_resource("planetscale", "shop/dev").status

    delete map_events_secrets_integration_path(row.integration), params: { environment_row_id: row.id }
    assert_equal "Signing secrets forgotten. Changes PlanetScale sends no longer reach the map until you add a secret again.", flash[:notice]
    assert_not row.reload.map_events_secret_set?
    delete map_events_secrets_integration_path(row.integration), params: { environment_row_id: row.id }
    assert_equal "No signing secret is saved for PlanetScale.", flash[:alert]
  end

  test "Supabase: a project event signed with the secret the admin chose re-reads the project, and Supabase's early access is said while off" do
    row = mcp_row("supabase", "Supabase", "https://mcp.supabase.com/mcp", %w[get_project list_branches])
    assert_equal "Send Supabase's changes to Firefight and save the signing secret under Integrations to turn them on. " \
                 "#{Integrations::MapEventSources::Supabase.by_hand_note}", row.live_updates.reason
    sign_in_admin
    patch map_events_secret_integration_path(row.integration), params: { environment_row_id: row.id, secret: "chosen-secret" }
    patch map_events_secret_integration_path(row.integration), params: { environment_row_id: row.id, secret: "replaced-secret" }
    assert_equal "replaced-secret", row.reload.map_events_secret, "Supabase keeps one secret, which saving again replaces"

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "supabase", account: "acme", kind: ResourceMap::KIND_DATABASE, external_id: "abcdefghijklmnopqrst", name: "shop", status: "ACTIVE_HEALTHY")
    ]))
    Integrations::McpClient.any_instance.stubs(:call_tool).with(name: "get_project", arguments: { "id" => "abcdefghijklmnopqrst" })
                           .returns(text_result("ref" => "abcdefghijklmnopqrst", "organization_slug" => "acme", "name" => "shop", "status" => "INACTIVE"))
    Integrations::McpClient.any_instance.stubs(:call_tool).with(name: "list_branches", arguments: anything).returns(text_result("branches" => []))

    body = { "id" => "evt-1", "type" => "v1.project.paused", "timestamp" => Time.current.utc.iso8601,
             "payload" => { "project_ref" => "abcdefghijklmnopqrst", "organization_slug" => "acme", "reason" => "inactivity", "actor" => nil } }.to_json
    stamp = Time.current.to_i.to_s
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "replaced-secret", "evt-1.#{stamp}.#{body}"))
    post api_v1_map_events_path(row.map_events_token), params: body,
                                                       headers: { "webhook-id" => "evt-1", "webhook-timestamp" => stamp, "webhook-signature" => "v1,#{signature}", "Content-Type" => "application/json" }
    assert_response :ok

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "paused", map_resource("supabase", "abcdefghijklmnopqrst").status
  end

  private

  def railway_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway", slug: "railwaylive")
    row = integration.integration_environments.create!
    Integrations::Packs::Railway.store_credentials!(row, Integrations::Packs::Railway::API_TOKEN => "rw-token")
    row.store_fields!(Integrations::Packs::Railway::PROJECT => "prj-1", Integrations::Packs::Railway::ENVIRONMENT => "production")
    Integrations::RailwayApi.any_instance.stubs(:project).with("prj-1")
                            .returns("id" => "prj-1", "workspaceId" => "ws-1", "environments" => { "edges" => [ { "node" => { "id" => "env-prod", "name" => "production" } } ] })
    row
  end

  def mcp_row(provider, name, server_url, tools)
    integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: provider, name: name, slug: "#{provider}live",
                                                  settings: { "server_url" => server_url })
    tools.each { |tool| integration.tools.create!(name: tool, read_only: true, enabled: true, params_schema: { "type" => "object" }) }
    row = integration.integration_environments.create!
    row.give_map_events_token!
    row
  end

  def sign_in_admin
    sign_in(users(:alice), @workspace)
  end

  def railway_service(id, status)
    ResourceMap::Found.new(provider: "railway", account: "prj-1/env-prod", kind: ResourceMap::KIND_SERVICE, external_id: id, name: id, status: status.downcase)
  end

  def railway_delivery(type, service)
    { "type" => type, "details" => { "id" => "dep-2" }, "severity" => "CRITICAL", "timestamp" => Time.current.utc.iso8601,
      "resource" => { "project" => { "id" => "prj-1" }, "environment" => { "id" => "env-prod" }, "service" => { "id" => service } } }.to_json
  end

  def railway_headers(secret) = { Integrations::MapEventSources::Railway::SECRET_HEADER => secret, "Content-Type" => "application/json" }

  def text_result(body) = { "content" => [ { "type" => "text", "text" => body.to_json } ] }

  def map_resource(provider, id) = ResourceMap::Resource.find_by!(workspace: @workspace, provider: provider, external_id: id)
end
