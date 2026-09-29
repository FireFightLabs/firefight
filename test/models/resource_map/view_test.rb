require "test_helper"

class ResourceMap::ViewTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    web, builder, repository = found("web"), found("builder"), found("repository")
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [ web, builder, repository ], links: [
      ResourceMap::FoundLink.new(from: web.key, to: builder.key, relation: ResourceMap::RELATION_RUNS_BUILDS_OF),
      ResourceMap::FoundLink.new(from: builder.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
    ]))
  end

  test "what depends on a resource counts everything that reaches it, directly or through others" do
    rows = ResourceMap::View.new(@workspace).rows.index_by { |row| row.resource.external_id }

    assert_equal [ "web", "builder" ].sort, names(rows["repository"].dependent_ids).sort
    assert_equal [ "web" ], names(rows["builder"].dependent_ids)
    assert_empty rows["web"].dependent_ids
  end

  test "an open incident on a catalog service lights up the resources that service runs on" do
    web = resource("web")
    entry = catalog_entries(:auth_service)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: entry, resource: web)
    incident = incidents(:active_critical_ws1)
    IncidentFieldValue.create!(incident: incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: entry)

    row = ResourceMap::View.new(@workspace).rows.find { |each| each.resource == web }

    assert_equal [ entry ], row.entries
    assert_equal [ incident ], row.open_incidents
    assert_equal 1, row.recent_incident_count
  end

  test "a dismissed suggestion is not part of the map" do
    link = ResourceMap::Link.suggest!(from: resource("repository"), to: resource("web"), relation: ResourceMap::RELATION_USES, note: "guess")
    link.dismiss!

    assert_not_includes ResourceMap::View.new(@workspace).links, link
    assert_match "dismissed", ResourceMap::Link.suggest!(from: resource("repository"), to: resource("web"), relation: ResourceMap::RELATION_USES, note: "again")
  end

  private

  def found(id) = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: id, name: id)

  def resource(id) = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: id)

  def names(ids) = ResourceMap::Resource.where(id: ids).pluck(:external_id)
end
