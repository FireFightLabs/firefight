# A map across two environments of the first workspace, for tests about who reads which part of it. web and orders-db
# run in Production, dev-worker and secret-db in Development, and shop.example.com is reported only by a connection
# wired to no environment. A person linked web to dev-worker, so a sheet of web has a link that leaves Production.
module TwoEnvironmentMapHelper
  HIDDEN_NAMES = %w[dev-worker secret-db shop.example.com].freeze

  def build_two_environment_map(workspace)
    northflank = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @production_row = northflank.integration_environments.create!(environment: catalog_entries(:production_env))
    @development_row = northflank.integration_environments.create!(environment: catalog_entries(:development_env))
    record_map(@production_row, "web", "orders-db", gap: "Jobs could not be read in Production")
    record_map(@development_row, "dev-worker", "secret-db", gap: "Jobs could not be read in secret-db's project")

    unscoped = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank edge", slug: "northflank_edge")
    ResourceMap.record!(unscoped.integration_environments.create!,
                        ResourceMap::Snapshot.new(resources: [ map_found("shop.example.com", ResourceMap::KIND_DOMAIN) ], links: [], gaps: []))

    ResourceMap::Link.create!(workspace: workspace, from_resource: map_resource(workspace, "web"), to_resource: map_resource(workspace, "dev-worker"),
                              relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_PERSON, last_seen_at: Time.current)
  end

  # Grants map.read in those environments alone, the way the Permissions screen does.
  def limit_map_to(workspace, principal, *environments)
    Ability::Grant.grant!(workspace: workspace, principal: principal, target: { action: Ability::Action.system!(Ability::Action::MAP_READ) },
                          environment_ids: environments.map(&:id))
  end

  def map_resource(workspace, name) = ResourceMap::Resource.find_by!(workspace: workspace, name: name)

  def map_found(name, kind = ResourceMap::KIND_SERVICE)
    ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: kind, external_id: name, name: name, status: "running",
                           url: "https://example.test/#{name}")
  end

  private

  def record_map(row, service, database, gap:)
    service_found = map_found(service)
    database_found = map_found(database, ResourceMap::KIND_DATABASE)
    ResourceMap.record!(row, ResourceMap::Snapshot.new(
      resources: [ service_found, database_found ],
      links: [ ResourceMap::FoundLink.new(from: service_found.key, to: database_found.key, relation: ResourceMap::RELATION_USES) ],
      gaps: [ ResourceMap::Gap.new(text: gap, kinds: []) ]
    ))
  end
end
