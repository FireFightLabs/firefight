require "test_helper"

# Render's and Vercel's changes from registration to the map. Firefight registers the webhook with the connection's own
# credentials, a signed delivery reaches the connection's address, and the scope it names is read again and written.
class LiveUpdatesRenderVercelTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  RENDER_SECRET = "whsec_#{Base64.strict_encode64('render signing key')}".freeze
  VERCEL_SECRET = "vercel-signing-secret".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "Render: a signed deploy event re-reads the service it names, a stale or forged one is refused, and a deleted service goes" do
    row = render_row
    # A workspace that already has a webhook of its own has room for Firefight's without a person deciding.
    Integrations::RenderApi.any_instance.stubs(:webhooks).returns(Integrations::Pages::Read.new(items: [ { "id" => "whk-theirs", "url" => "https://example.com" } ], complete: true))
    Integrations::RenderApi.any_instance.expects(:create_webhook).with("tea-1", has_entries(events: Integrations::MapEventSources::Render::EVENTS))
                           .returns("id" => "whk-1", "secret" => RENDER_SECRET)
    with_app_host { Integrations::MapEvents.prepare!(row) }
    assert_equal [ "whk-1", true ], [ row.reload.map_events_webhook_id, row.live_updates.on ]

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ render_service("live"), render_service("live", id: "srv-old", name: "old") ]))
    stub_render_service("build_failed")

    body = { "type" => "deploy_ended", "timestamp" => 1.minute.ago.utc.iso8601,
             "data" => { "id" => "evt-1", "serviceId" => "srv-web", "serviceName" => "web", "status" => "failed" } }.to_json
    post api_v1_map_events_path(row.map_events_token), params: body, headers: render_signed(body, "evt-1", at: 7.minutes.ago)
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: body, headers: render_signed(body, "evt-1").merge("webhook-signature" => "v1,Zm9yZ2Vk")
    assert_response :unauthorized
    assert_not ResourceMap::ReceivedEvent.exists?(integration_environment: row)

    2.times do
      post api_v1_map_events_path(row.map_events_token), params: body, headers: render_signed(body, "evt-1")
      assert_response :ok
    end
    assert_equal 1, ResourceMap::ReceivedEvent.where(integration_environment: row).count, "a retry with the same webhook-id is kept once"

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "failed", map_resource("render", "srv-web").status

    Integrations::RenderApi.any_instance.stubs(:service).with("srv-old").raises(Integrations::RenderApi::NotFound, "Render answered 404: not found")
    gone = { "type" => "service_suspended", "timestamp" => Time.current.utc.iso8601, "data" => { "id" => "evt-2", "serviceId" => "srv-old" } }.to_json
    post api_v1_map_events_path(row.map_events_token), params: gone, headers: render_signed(gone, "evt-2")
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert map_resource("render", "srv-old").removed_at.present?
  end

  test "Render: a workspace without room for a webhook is off with the reason, and removing a connection takes back only Firefight's" do
    row = render_row
    Integrations::RenderApi.any_instance.stubs(:webhooks).returns(Integrations::Pages::Read.new(items: [ { "id" => "whk-theirs", "url" => "https://example.com", "enabled" => true } ], complete: true))
    Integrations::RenderApi.any_instance.stubs(:create_webhook).raises(Integrations::RenderApi::Refused, "Render answered 400: webhook limit reached")
    Integrations::RenderApi.any_instance.expects(:delete_webhook).never
    with_app_host { Integrations::MapEvents.prepare!(row) }

    state = row.reload.live_updates
    assert_not state.on
    assert_equal "Firefight could not follow Render's changes: Render answered 400: webhook limit reached. " \
                 "#{Integrations::MapEventSources::Render::PLAN_NOTE}. Firefight tries again tomorrow. The map still updates at each sweep.", state.reason
    Integrations::MapEvents.connection_removed(row.integration)

    row.update!(map_events_webhook_id: "whk-1", map_events_secret: RENDER_SECRET, map_events_error: nil)
    Integrations::RenderApi.any_instance.unstub(:delete_webhook)
    Integrations::RenderApi.any_instance.expects(:delete_webhook).with("whk-1").returns({})
    Integrations::MapEvents.connection_removed(row.integration)
    assert_nil row.reload.map_events_webhook_id
    assert_equal "remove", Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP).order(:created_at).last.params["webhook"]
  end

  test "Render: a workspace with no webhooks waits for a person, since Firefight's could be its only one" do
    row = render_row
    Integrations::RenderApi.any_instance.stubs(:webhooks).returns(Integrations::Pages::Read.new(items: [], complete: true))
    Integrations::RenderApi.any_instance.expects(:create_webhook).once.returns("id" => "whk-1", "secret" => RENDER_SECRET)
    Integrations::RenderApi.any_instance.expects(:delete_webhook).with("whk-1").returns({})

    with_app_host do
      Integrations::MapEvents.prepare!(row)
      Integrations::MapEvents.prepare!(row)
      assert_equal "Firefight asks before adding its webhook to Render. #{Integrations::MapEventSources::Render::ONLY_WEBHOOK}", row.reload.live_updates.reason

      Integrations::MapEvents.turn_on!(row)
      assert row.reload.live_updates.on
      assert_equal Integrations::MapEventSources::Render::ONLY_WEBHOOK, row.map_events_confirmation, "the person who turned it on can turn it off"
      Integrations::MapEvents.turn_off!(row)
    end
    assert_not row.reload.live_updates.on
  end

  test "Vercel: a signed production deployment re-reads its project, a forged one is refused, and a removed project goes" do
    row = vercel_row
    Integrations::VercelApi.any_instance.stubs(:webhooks).returns([])
    Integrations::VercelApi.any_instance.expects(:create_webhook).with(has_entries(events: Integrations::MapEventSources::Vercel::EVENTS))
                           .returns("id" => "hook_1", "secret" => VERCEL_SECRET)
    with_app_host { Integrations::MapEvents.prepare!(row) }
    assert row.reload.live_updates.on

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ vercel_project("ready"), vercel_project("ready", id: "prj_old", name: "old") ]))
    Integrations::VercelApi.any_instance.stubs(:project).with("prj_1").returns(
      "id" => "prj_1", "name" => "shop", "accountId" => "team_1", "targets" => { "production" => { "id" => "dpl_3", "readyState" => "ERROR" } }
    )
    Integrations::VercelApi.any_instance.stubs(:project_domains).returns(Integrations::Pages::Read.new(items: [], complete: true))
    Integrations::VercelApi.any_instance.stubs(:project_env).returns([ [], false ])
    Integrations::VercelApi.any_instance.stubs(:team).returns("slug" => "acme")

    body = vercel_delivery("evt_1", "deployment.error", "prj_1", "target" => "production", "deployment" => { "id" => "dpl_3" })
    post api_v1_map_events_path(row.map_events_token), params: body, headers: { "x-vercel-signature" => OpenSSL::HMAC.hexdigest("SHA1", "forged", body) }
    assert_response :unauthorized
    post api_v1_map_events_path(row.map_events_token), params: body, headers: vercel_signed(body)
    assert_response :ok
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "error", map_resource("vercel", "prj_1").status

    Integrations::VercelApi.any_instance.stubs(:project).with("prj_old").raises(Integrations::VercelApi::NotFound, "Vercel answered 404: Project not found")
    removed = vercel_delivery("evt_2", "project.removed", "prj_old")
    post api_v1_map_events_path(row.map_events_token), params: removed, headers: vercel_signed(removed)
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert map_resource("vercel", "prj_old").removed_at.present?
  end

  private

  def render_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render", slug: "render")
    row = integration.integration_environments.create!
    Integrations::Packs::Render.store_credentials!(row, Integrations::Packs::Render::API_KEY => "rnd_key")
    row.store_fields!(Integrations::Packs::Render::WORKSPACE => "tea-1")
    row
  end

  def vercel_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "vercel", name: "Vercel", slug: "vercel")
    row = integration.integration_environments.create!
    Integrations::Packs::Vercel.store_credentials!(row, Integrations::Packs::Vercel::API_TOKEN => "tok")
    row.store_fields!(Integrations::Packs::Vercel::TEAM => "team_1")
    row
  end

  def render_service(status, id: "srv-web", name: "web")
    ResourceMap::Found.new(provider: "render", account: "tea-1", kind: ResourceMap::KIND_SERVICE, external_id: id, name: name, status: status)
  end

  def vercel_project(status, id: "prj_1", name: "shop")
    ResourceMap::Found.new(provider: "vercel", account: "team_1", kind: ResourceMap::KIND_SITE, external_id: id, name: name, status: status)
  end

  def stub_render_service(status)
    Integrations::RenderApi.any_instance.stubs(:service).with("srv-web").returns("id" => "srv-web", "name" => "web", "type" => "background_worker", "suspended" => "not_suspended")
    Integrations::RenderApi.any_instance.stubs(:deploys).returns([ { "id" => "dep-2", "status" => status } ])
    Integrations::RenderApi.any_instance.stubs(:env_vars).returns(Integrations::Pages::Read.new(items: [], complete: true))
    Integrations::RenderApi.any_instance.stubs(:env_groups).returns([])
  end

  def map_resource(provider, id) = ResourceMap::Resource.find_by!(workspace: @workspace, provider: provider, external_id: id)

  def render_signed(body, id, at: Time.current)
    key = Base64.decode64(RENDER_SECRET.delete_prefix("whsec_"))
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{at.to_i}.#{body}"))
    { "webhook-id" => id, "webhook-timestamp" => at.to_i.to_s, "webhook-signature" => "v1,#{signature}", "Content-Type" => "application/json" }
  end

  def vercel_delivery(id, type, project, **payload)
    { "id" => id, "type" => type, "createdAt" => (Time.current.to_f * 1000).to_i,
      "payload" => { "team" => { "id" => "team_1" }, "project" => { "id" => project } }.merge(payload.stringify_keys) }.to_json
  end

  def vercel_signed(body) = { "x-vercel-signature" => OpenSSL::HMAC.hexdigest("SHA1", VERCEL_SECRET, body), "Content-Type" => "application/json" }
end
