require "test_helper"

class ResourceMapControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    web = found(ResourceMap::KIND_SERVICE, "web")
    builder = found(ResourceMap::KIND_BUILD_SERVICE, "builder")
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ web, builder, found(ResourceMap::KIND_DATABASE, "db") ],
                                                        links: [ ResourceMap::FoundLink.new(from: web.key, to: builder.key, relation: ResourceMap::RELATION_RUNS_BUILDS_OF) ],
                                                        gaps: [ "Jobs could not be read" ]))
  end

  test "the page lists every resource with what depends on it, the links and what each connection could not read" do
    props = inertia_props(resource_map_path)

    builder = props["resources"].find { |resource| resource["name"] == "builder" }
    assert_equal [ resource("web").id ], builder["dependentIds"]
    assert_equal "Northflank", builder["providerName"]
    link = props["links"].sole
    assert_equal ResourceMap::ORIGIN_DECLARED, link["origin"]
    assert_equal "Northflank", link["foundBy"]
    assert_match "goes when the connection stops reporting it", link["removalBlockedReason"]
    assert_equal [ "Jobs could not be read" ], props["connections"].sole["gaps"]
  end

  test "a person adds a link, can remove it, and cannot remove one a provider reports" do
    post resource_map_links_path, params: { from_id: resource("web").id, to_id: resource("db").id, relation: ResourceMap::RELATION_USES, note: "DATABASE_URL" }
    added = ResourceMap::Link.find_by!(from_resource: resource("web"), to_resource: resource("db"))
    assert_equal ResourceMap::ORIGIN_PERSON, added.origin
    assert_equal "Added: web uses db.", flash[:notice]

    delete resource_map_link_path(ResourceMap::Link.find_by!(origin: ResourceMap::ORIGIN_DECLARED, workspace: @workspace))
    assert_match "goes when the connection stops reporting it", flash[:alert]

    delete resource_map_link_path(added)
    assert_not ResourceMap::Link.exists?(added.id)
  end

  test "a suggestion is confirmed or dismissed once, and a second decision is told it was already made" do
    link = ResourceMap::Link.suggest!(from: resource("web"), to: resource("db"), relation: ResourceMap::RELATION_USES, note: "host in logs")

    post confirm_resource_map_link_path(link)
    assert link.reload.confirmed_at
    assert_equal "Confirmed: web uses db.", flash[:notice]

    post dismiss_resource_map_link_path(link)
    assert_equal "Someone already decided on this suggestion.", flash[:alert]
    assert_nil link.reload.dismissed_at
  end

  test "a resource is linked to the catalog entry it runs, and unlinked" do
    entry = catalog_entries(:auth_service)

    post resource_map_resource_entries_path(resource("web")), params: { catalog_entry_id: entry.id }
    assert_equal [ entry ], resource("web").catalog_entries
    assert_equal "web now runs Auth Service.", flash[:notice]

    delete resource_map_resource_entry_path(resource("web"), entry)
    assert_empty resource("web").catalog_entries
  end

  test "sync now sweeps every connection" do
    post resource_map_sync_path

    assert_enqueued_with(job: Integrations::MapSweepJob, args: [ @row ])
    assert_equal "Syncing 1 connection. The map updates as each one finishes.", flash[:notice]
  end

  test "a resource carries what Halon remembers about it and the instructions for it and the entry it runs, never rejected memories" do
    entry = catalog_entries(:auth_service)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: entry, resource: resource("web"))
    kept = Chat::Memory.create!(workspace: @workspace, text: "web serves checkout", subject: resource("web"), state: Chat::Memory::STATE_CONFIRMED)
    Chat::Memory.create!(workspace: @workspace, text: "web is in Frankfurt", subject: resource("web"), state: Chat::Memory::STATE_REJECTED)
    note = Chat::Instruction.create!(workspace: @workspace, scope: entry, text: "Check the session store first")

    web = inertia_props(resource_map_path)["resources"].find { |each| each["name"] == "web" }

    assert_equal [ [ kept.id, Chat::Memory::STATE_CONFIRMED, "web serves checkout" ] ], web["memories"]
    assert_equal [ [ note.id, "Auth Service (service)", "Check the session store first" ] ], web["instructions"]
  end

  test "a resource carries what its catalog service is for, who owns it, and how its recent incidents ended" do
    entry = catalog_entries(:auth_service)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: entry, resource: resource("web"))
    IncidentFieldValue.create!(incident: incidents(:resolved_minor_ws1), incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: entry)

    web = inertia_props(resource_map_path)["resources"].find { |each| each["name"] == "web" }

    assert_equal [ "Handles authentication.", [ "Platform Team" ] ], web["catalogEntries"].sole.values_at("purpose", "owners")
    past = web["pastIncidents"].sole
    assert_equal [ "INC-003", "Users unable to upload profile images", Incident::Outcome::SOURCE_SUMMARY ], past.values_at("identifier", "outcome", "outcomeSource")
  end

  test "a resource carries what normal looks like for its metrics, each amount with its unit" do
    now = Time.current
    ResourceMap::Baseline.record!(@row, [ resource("web") ], [ ResourceMap::Baseline::Found.new(key: resource("web").key, metric: "cpu", label: "CPU", unit: "vCPU", points: [ [ now, 0.2 ], [ now - 1.hour, 0.4 ] ]) ],
                                  window_from: now - 7.days, window_to: now)

    web = inertia_props(resource_map_path)["resources"].find { |each| each["name"] == "web" }

    assert_equal [ "CPU", "0.3 vCPU", "0.39 vCPU", "0.4 vCPU" ], web["baselines"].sole.values_at("label", "typical", "high", "peak")
  end

  test "someone who may not change the catalog cannot change links" do
    AbilityGateway.stubs(:permitted?).returns(false)

    post resource_map_links_path, params: { from_id: resource("web").id, to_id: resource("db").id, relation: ResourceMap::RELATION_USES }

    assert_not ResourceMap::Link.exists?(from_resource: resource("web"), to_resource: resource("db"))
  end

  private

  def found(kind, id) = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: kind, external_id: id, name: id)

  def resource(id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: id)

  def inertia_props(url)
    get url, headers: { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s }
    JSON.parse(response.body).fetch("props")
  end
end
