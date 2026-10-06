require "test_helper"

# Northflank's, Netlify's, Google Cloud's and Azure's changes from the provider to the map. Northflank and Netlify send
# them to a webhook Firefight adds with the connection's own credentials, and Google Cloud's audit log and Azure's activity
# log are read every five minutes. Either way the scope named is read again and written.
class LiveUpdatesNorthflankNetlifyGoogleCloudAzureTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include LiveUpdatesTestHelper

  SUBSCRIPTION = "11111111-2222-3333-4444-555555555555".freeze
  WEB_ID = "/subscriptions/#{SUBSCRIPTION}/resourceGroups/shop/providers/Microsoft.Web/sites/storefront".freeze
  VM_ID = "projects/acme-prod/zones/us-central1-a/instances/worker-1".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "Northflank: a delivery carrying the integration's secret re-reads the service it names, and one without is refused" do
    row = northflank_row
    Integrations::NorthflankApi.any_instance.stubs(:notifications).returns(Integrations::Pages::Read.new(items: [], complete: true))
    Integrations::NorthflankApi.any_instance.expects(:create_notification).returns("id" => "firefight-live-updates")
    with_app_host { Integrations::MapEvents.prepare!(row) }
    row.reload
    assert_equal [ "firefight-live-updates", true ], [ row.map_events_webhook_id, row.live_updates.on ]
    assert_equal Integrations::MapEventSources::Northflank.limits, row.live_updates.reason

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web", status: "completed")
    ]))
    Integrations::NorthflankApi.any_instance.stubs(:service).with("shop", "web").returns(
      "id" => "web", "name" => "web", "serviceType" => "deployment", "appId" => "/acme/shop/web", "status" => { "deployment" => { "status" => "FAILED" } }
    )
    Integrations::NorthflankApi.any_instance.stubs(:secret_groups).returns(Integrations::Pages::Read.new(items: [], complete: true))
    body = { "event" => "service:deployment:status-update", "data" => { "service" => { "id" => "web" }, "project" => { "id" => "shop" } } }.to_json

    post api_v1_map_events_path(row.map_events_token), params: body, headers: { "X-Northflank-Notification-Integration-Token" => "forged", "Content-Type" => "application/json" }
    assert_response :unauthorized
    2.times do
      post api_v1_map_events_path(row.map_events_token), params: body,
                                                         headers: { "X-Northflank-Notification-Integration-Token" => row.map_events_secret,
                                                                    "X-Northflank-Notification-Integration-Event-Id" => "evt-1", "Content-Type" => "application/json" }
      assert_response :ok
    end
    assert_equal 1, ResourceMap::ReceivedEvent.where(integration_environment: row).count

    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "failed", map_resource("northflank", "web").status
  end

  test "Netlify: a deploy signed with the hooks' secret re-reads its site, and a new site gets hooks at the next sweep" do
    row = netlify_row
    Integrations::NetlifyApi.any_instance.stubs(:sites).returns(Integrations::Pages::Read.new(items: [ { "id" => "site-1", "account_id" => "acc-1" } ], complete: true))
    Integrations::NetlifyApi.any_instance.stubs(:hook_types).returns([ { "name" => "url", "events" => Integrations::MapEventSources::Netlify::EVENTS } ])
    Integrations::NetlifyApi.any_instance.stubs(:hooks).returns([])
    Integrations::NetlifyApi.any_instance.expects(:create_hook).twice.returns({})
    with_app_host { Integrations::MapEvents.prepare!(row) }
    row.reload
    assert_equal [ Integrations::MapEventSources::Netlify::ALL_SITES, true ], [ row.map_events_webhook_id, row.live_updates.on ]

    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "netlify", account: "acme", kind: ResourceMap::KIND_SITE, external_id: "site-1", name: "shop", details: { "deploy" => "d2" })
    ]))
    Integrations::NetlifyApi.any_instance.stubs(:site).with("site-1").returns(
      "id" => "site-1", "name" => "shop", "account_id" => "acc-1", "account_slug" => "acme", "state" => "current", "published_deploy" => { "id" => "d3", "commit_ref" => "fedcba" }
    )
    Integrations::NetlifyApi.any_instance.stubs(:env_vars).returns([])
    body = { "id" => "d3", "site_id" => "site-1", "context" => "production", "updated_at" => Time.current.utc.iso8601 }.to_json
    signature = JWT.encode({ "iss" => "netlify", "sha256" => Digest::SHA256.hexdigest(body) }, row.map_events_secret, "HS256")

    post api_v1_map_events_path(row.map_events_token), params: body, headers: { "X-Netlify-Event" => "deploy_created", "X-Webhook-Signature" => signature, "Content-Type" => "application/json" }
    assert_response :ok
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal [ "d3", "fedcba" ], map_resource("netlify", "site-1").details.values_at("deploy", ResourceMap::DEPLOYED_COMMIT)

    Integrations::NetlifyApi.any_instance.stubs(:sites).returns(Integrations::Pages::Read.new(items: [ { "id" => "site-1", "account_id" => "acc-1" }, { "id" => "site-2", "account_id" => "acc-1" } ], complete: true))
    with_app_host do
      Integrations::NetlifyApi.any_instance.stubs(:hooks).with("site-1").returns(Integrations::MapEventSources::Netlify::EVENTS.map { |event| own_hook(row, event) })
      Integrations::NetlifyApi.any_instance.stubs(:hooks).with("site-2").returns([])
      Integrations::NetlifyApi.any_instance.expects(:create_hook).twice.with { |site, **| site == "site-2" }.returns({})
      Integrations::MapEvents.prepare!(row.reload)
    end
  end

  test "Google Cloud: each five minutes the audit log is read after the cursor, and the instance an entry names is read again" do
    row = google_cloud_row
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "google_cloud", account: "acme-prod", kind: ResourceMap::KIND_VIRTUAL_MACHINE, external_id: VM_ID, name: "worker-1", status: "running")
    ]))
    Integrations::GoogleCloudApi.any_instance.stubs(:log_entries_since).returns(Integrations::Pages::Read.new(items: [
      { "insertId" => "e1", "timestamp" => 1.minute.ago.utc.iso8601,
        "protoPayload" => { "serviceName" => "compute.googleapis.com", "methodName" => "v1.compute.instances.stop", "resourceName" => VM_ID } }
    ], complete: true))
    Integrations::GoogleCloudApi.any_instance.stubs(:compute_instance).with("acme-prod", "us-central1-a", "worker-1").returns(
      "name" => "worker-1", "status" => "TERMINATED", "zone" => "zones/us-central1-a", "selfLink" => "https://www.googleapis.com/compute/v1/#{VM_ID}"
    )

    Integrations::MapEventPollJob.perform_now(row)
    assert row.reload.map_events_cursor.present?
    assert_not ResourceMap::ReceivedEvent.exists?(integration_environment: row), "the first read starts from now"

    Integrations::MapEventPollJob.perform_now(row)
    perform_enqueued_jobs(only: Integrations::MapEventJob)
    assert_equal "stopped", map_resource("google_cloud", VM_ID).status
    assert_equal [ true, Integrations::MapEventSources::GoogleCloud.limits ], [ row.reload.live_updates.on, row.live_updates.reason ]

    Integrations::GoogleCloudApi.any_instance.stubs(:log_entries_since).raises(Integrations::GoogleCloudApi::Forbidden, "Google Cloud answered 403: Permission denied")
    Integrations::MapEventPollJob.perform_now(row)
    assert_not row.reload.live_updates.on
    assert_equal "Firefight could not follow Google Cloud's changes: Google Cloud answered 403: Permission denied. The map still updates at each sweep.", row.live_updates.reason
  end

  test "Azure: each five minutes the activity log is read, and an app deleted there is taken off the map" do
    row = azure_row
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "azure", account: SUBSCRIPTION, kind: ResourceMap::KIND_SERVICE, external_id: WEB_ID, name: "storefront", status: "running")
    ]))
    Integrations::AzureApi.any_instance.stubs(:activity_log).returns(Integrations::Pages::Read.new(items: [
      { "eventDataId" => "e1", "eventTimestamp" => 2.minutes.ago.utc.iso8601, "operationName" => { "value" => "Microsoft.Web/sites/delete" },
        "resourceId" => WEB_ID.downcase, "status" => { "value" => "Succeeded" } }
    ], complete: true))
    Integrations::AzureApi.any_instance.stubs(:get).with(WEB_ID, Integrations::Packs::Azure::WEB_VERSION).raises(Integrations::AzureApi::NotFound, "Azure answered 404: ResourceNotFound")

    Integrations::MapEventPollJob.perform_now(row)
    Integrations::MapEventPollJob.perform_now(row)
    perform_enqueued_jobs(only: Integrations::MapEventJob)

    assert map_resource("azure", WEB_ID).removed_at.present?
    assert_equal Integrations::MapEventSources::Azure.limits, row.reload.live_updates.reason
  end

  private

  def northflank_row
    row = connection("northflank", "Northflank")
    Integrations::Packs::Northflank.store_credentials!(row, Integrations::Packs::Northflank::API_TOKEN => "nf-token")
    row.store_fields!(Integrations::Packs::Northflank::PROJECT => "shop")
    row
  end

  def netlify_row
    row = connection("netlify", "Netlify")
    Integrations::Packs::Netlify.store_credentials!(row, Integrations::Packs::Netlify::API_TOKEN => "nfp-token")
    row
  end

  def google_cloud_row
    row = connection("google_cloud", "Google Cloud")
    Integrations::Packs::GoogleCloud.store_credentials!(row, Integrations::Packs::GoogleCloud::KEY => { "type" => "service_account", "client_email" => "ff@acme-prod.iam.gserviceaccount.com", "private_key" => "pem" }.to_json)
    row.store_fields!(Integrations::Packs::GoogleCloud::PROJECT => "acme-prod")
    Integrations::MapEvents.prepare!(row)
    row
  end

  def azure_row
    row = connection("azure", "Azure")
    Integrations::Packs::Azure.store_credentials!(row, Integrations::Packs::Azure::SECRET => "s3cret")
    row.store_fields!(Integrations::Packs::Azure::TENANT => "contoso.onmicrosoft.com", Integrations::Packs::Azure::CLIENT => "22222222-2222-3333-4444-555555555555",
                      Integrations::Packs::Azure::SUBSCRIPTION => SUBSCRIPTION)
    Integrations::MapEvents.prepare!(row)
    row
  end

  def connection(provider, name)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: provider, name: name, slug: provider).integration_environments.create!
  end

  def own_hook(row, event)
    { "id" => "h-#{event}", "type" => "url", "event" => event, "data" => { "url" => Integrations::MapEvents.url_for(row) } }
  end

  def map_resource(provider, id) = ResourceMap::Resource.find_by!(workspace: @workspace, provider: provider, external_id: id)
end
