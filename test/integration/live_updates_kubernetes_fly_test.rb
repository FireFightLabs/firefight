require "test_helper"

# Kubernetes' and Fly.io's changes from their poll to the map. Firefight follows each with its own reads on a schedule,
# and the object a change names is read again and written.
class LiveUpdatesKubernetesFlyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include KubernetesTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Integrations::PublicAddress.stubs(:resolve).returns(IPAddr.new("203.0.113.10"))
  end

  test "Kubernetes: a watched change re-reads the workload, and a token that may not watch says what to allow" do
    row = kubernetes_row
    Integrations::KubernetesApi.any_instance.stubs(:get).with { |_path, query = {}| query == { "limit" => 1 } }.returns("metadata" => { "resourceVersion" => "100" })
    Integrations::KubernetesApi.any_instance.stubs(:watch)
    Integrations::MapEventPollJob.perform_now(row)
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ workload("running") ]))

    changed = { "type" => "MODIFIED", "object" => { "metadata" => { "name" => "web", "namespace" => "production", "uid" => "u1", "resourceVersion" => "120" } } }
    Integrations::KubernetesApi.any_instance.stubs(:watch).with("/apis/apps/v1/namespaces/production/deployments", resource_version: "100").yields(changed)
    Integrations::KubernetesApi.any_instance.stubs(:get).with("/apis/apps/v1/namespaces/production/deployments/web").returns(
      "metadata" => { "name" => "web", "namespace" => "production" }, "spec" => { "replicas" => 0 }, "status" => {}
    )
    row.update!(map_events_polled_at: nil)
    Integrations::MapEventPollJob.perform_now(row)
    assert row.reload.live_updates.on
    perform_enqueued_jobs(only: Integrations::MapEventJob)

    assert_equal "stopped", ResourceMap::Resource.find_by!(workspace: @workspace, provider: "kubernetes", external_id: "production/deployment/web").status

    Integrations::KubernetesApi.any_instance.stubs(:watch).with("/apis/apps/v1/namespaces/production/deployments", resource_version: "120")
                               .raises(Integrations::KubernetesApi::Forbidden, "The API server answered 403: forbidden")
    row.update!(map_events_polled_at: nil)
    Integrations::MapEventPollJob.perform_now(row)
    state = row.reload.live_updates
    assert_not state.on
    assert_equal "Firefight could not follow Kubernetes's changes: The token's role may not watch deployments in production, which following " \
                 "changes as they happen needs. Allow watch beside get and list on what Firefight reads. Firefight tries again tomorrow. " \
                 "The map still updates at each sweep.", state.reason
  end

  test "Fly.io: an app whose machines changed is read again, and one removed goes" do
    row = fly_row
    Integrations::FlyApi.any_instance.stubs(:app_list).returns(Integrations::Pages::Read.new(items: [ { "name" => "web", "status" => "deployed" }, { "name" => "old" } ], complete: true))
    machines("web", "started")
    machines("old", "started")
    Integrations::MapEventSources::Fly.stubs(:pause)
    Integrations::MapEventPollJob.perform_now(row)
    ResourceMap.record!(row, ResourceMap::Snapshot.new(resources: [ fly_app("web", "deployed"), fly_app("old", "deployed") ]))

    machines("web", "stopped")
    Integrations::FlyApi.any_instance.stubs(:app_list).returns(Integrations::Pages::Read.new(items: [ { "name" => "web", "status" => "suspended" } ], complete: true))
    Integrations::FlyApi.any_instance.stubs(:app).with("web").returns("name" => "web", "status" => "suspended")
    Integrations::FlyApi.any_instance.stubs(:app).with("old").raises(Integrations::FlyApi::NotFound, "Fly answered 404: not found")
    Integrations::FlyApi.any_instance.stubs(:certificates).returns(Integrations::Pages::Read.new(items: [], complete: true))
    Integrations::FlyApi.any_instance.stubs(:secret_names).returns([])
    Integrations::FlyApi.any_instance.stubs(:postgres_clusters).returns([])
    row.update!(map_events_polled_at: nil)
    Integrations::MapEventPollJob.perform_now(row)
    perform_enqueued_jobs(only: Integrations::MapEventJob)

    assert_equal "stopped", ResourceMap::Resource.find_by!(workspace: @workspace, provider: "fly", external_id: "web").status
    assert ResourceMap::Resource.find_by!(workspace: @workspace, provider: "fly", external_id: "old").removed_at.present?
  end

  private

  def kubernetes_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "kubernetes", name: "Kubernetes", slug: "kubernetes")
    row = integration.integration_environments.create!
    Integrations::Packs::Kubernetes.store_credentials!(row, Integrations::Packs::Kubernetes::TOKEN => "sa-token", Integrations::Packs::Kubernetes::CA => kubernetes_ca_pem)
    row.store_fields!(Integrations::Packs::Kubernetes::SERVER => "https://cluster.example.com", Integrations::Packs::Kubernetes::NAMESPACES => "production")
    row
  end

  def fly_row
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly.io", slug: "fly")
    row = integration.integration_environments.create!
    Integrations::Packs::Fly.store_credentials!(row, Integrations::Packs::Fly::API_TOKEN => "FlyV1 fm2_x")
    row.store_fields!(Integrations::Packs::Fly::ORGANIZATION => "acme")
    row
  end

  def workload(status)
    ResourceMap::Found.new(provider: "kubernetes", account: "cluster.example.com/production", kind: ResourceMap::KIND_SERVICE,
                           external_id: "production/deployment/web", name: "web", status: status)
  end

  def fly_app(name, status) = ResourceMap::Found.new(provider: "fly", account: "acme", kind: ResourceMap::KIND_SERVICE, external_id: name, name: name, status: status)

  def machines(app, state)
    Integrations::FlyApi.any_instance.stubs(:machines).with(app).returns([ { "id" => "m-#{app}", "state" => state, "updated_at" => Time.current.iso8601(6), "config" => {} } ])
  end
end
