require "test_helper"

class ResourceMap::BlastRadiusTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(environment: catalog_entries(:production_env))
    @database, @web, @builder, @domain, @worker = [
      found("orders", ResourceMap::KIND_DATABASE), found("web"), found("builder", ResourceMap::KIND_BUILD_SERVICE),
      found("shop.example.com", ResourceMap::KIND_DOMAIN), found("worker", ResourceMap::KIND_JOB)
    ].tap do |resources|
      database, web, builder, domain, = resources
      ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: resources, links: [
        ResourceMap::FoundLink.new(from: web.key, to: database.key, relation: ResourceMap::RELATION_USES),
        ResourceMap::FoundLink.new(from: builder.key, to: web.key, relation: ResourceMap::RELATION_RUNS_BUILDS_OF),
        ResourceMap::FoundLink.new(from: domain.key, to: web.key, relation: ResourceMap::RELATION_SERVED_BY),
        ResourceMap::FoundLink.new(from: domain.key, to: builder.key, relation: ResourceMap::RELATION_USES)
      ]))
    end.map { |each| ResourceMap::Resource.find_by!(workspace: @workspace, external_id: each.external_id) }
    ResourceMap::Link.suggest!(from: @worker, to: @database, relation: ResourceMap::RELATION_USES, note: "same project")
  end

  test "what fails with a resource is what the map page counts as its dependents, and suggestions are kept apart" do
    view = ResourceMap::View.new(@workspace, map_reader).rows.index_by(&:resource)

    [ @database, @web, @builder, @domain, @worker ].each do |resource|
      radius = ResourceMap::BlastRadius.new(resource)
      assert_equal view.fetch(resource).dependent_ids.sort, radius.dependent_ids.sort, resource.name
      assert_equal view.fetch(resource).suggested_dependent_ids.sort, radius.suggested_dependent_ids.sort, resource.name
    end
    assert_equal [ @worker.id ], ResourceMap::BlastRadius.new(@database).suggested_dependent_ids
  end

  test "dependents are counted by kind, provider and environment, and ranked by what depends on them in turn" do
    radius = ResourceMap::BlastRadius.new(@database)

    assert_equal 3, radius.total
    assert_equal({ ResourceMap::KIND_BUILD_SERVICE => 1, ResourceMap::KIND_DOMAIN => 1, ResourceMap::KIND_SERVICE => 1 }, radius.by_kind)
    assert_equal({ "northflank" => 3 }, radius.by_provider)
    assert_equal({ "Production" => 3 }, radius.by_environment)
    assert_equal [ @web, @builder, @domain ], radius.top_dependents
    assert_equal [ 2, 1, 0 ], radius.top_dependents.map(&:dependents_count)
  end

  test "the catalog services it and its dependents run come with their owning teams and open incidents" do
    service = catalog_entries(:auth_service)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: service, resource: @web)
    incident = incidents(:active_critical_ws1)
    IncidentFieldValue.create!(incident: incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: service)

    affected = ResourceMap::BlastRadius.new(@database).services.sole

    assert_equal [ service, [ catalog_entries(:platform_team) ], [ incident ] ], [ affected.entry, affected.owning_teams, affected.open_incidents ]
    assert_empty ResourceMap::BlastRadius.new(@domain).services
  end

  private

  def found(id, kind = ResourceMap::KIND_SERVICE) = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: kind, external_id: id, name: id)
end
