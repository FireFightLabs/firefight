# What would fail with a resource: everything with a path of fact links into it, the way ResourceMap::View counts a
# resource's dependents, read in a fixed number of queries whatever the map's size. What the suggestions would add if
# they are right is kept apart, never counted in.
class ResourceMap::BlastRadius
  TOP_SHOWN = 10

  Service = Data.define(:entry, :owning_teams, :open_incidents)

  attr_reader :root

  # hops bounds how many links a failure is followed along, as far as a walk goes by default.
  def initialize(root, within: nil, hops: ResourceMap::Graph::MAX_HOPS)
    @root = root
    @within = within
    @hops = hops
  end

  def graph = @graph ||= ResourceMap::Graph.new(root, direction: ResourceMap::Graph::DEPENDENTS, hops: @hops, within: @within)

  def dependents = graph.resources

  def dependent_ids = @dependent_ids ||= dependents.pluck(:id)

  def total = graph.total

  def suggested_dependent_ids
    @suggested_dependent_ids ||= ResourceMap::Graph.new(root, direction: ResourceMap::Graph::DEPENDENTS, suggestions: true, hops: @hops, within: @within)
                                                   .resources.where.not(id: dependents.select(:id)).pluck(:id)
  end

  def by_kind = tally(dependents.group(:kind))

  def by_provider = tally(dependents.group(:provider))

  # By the environment of the connection that reported each one, nil for a connection wired to none.
  def by_environment = tally(dependents.left_joins(integration_environment: :environment).group("catalog_entries.name"))

  # The dependents most others depend on in turn, by their own direct dependents.
  def top_dependents(limit: TOP_SHOWN)
    counted = dependents.select("resource_map_resources.*, #{ResourceMap::Query.dependents_sql('resource_map_resources.id', within: @within)} AS dependents_count")
    ResourceMap::Resource.from(counted, :resource_map_resources).order(dependents_count: :desc, name: :asc, id: :asc).limit(limit).to_a
  end

  # The catalog services the resource and its dependents run, each with who owns it and its open incidents.
  def services
    @services ||= begin
      entries = CatalogEntry.where(workspace_id: root.workspace_id, deleted_at: nil)
                            .where(id: ResourceMap::EntryLink.where(resource_id: ResourceMap::Resource.where(id: root.id).or(dependents).select(:id)).select(:catalog_entry_id))
                            .includes(:catalog_type, outgoing_relationships: { target_entry: :catalog_type }).order(:name).to_a
      incidents = IncidentFieldValue.joins(:incident).merge(Incident.active)
                                    .where(catalog_entry_id: entries.map(&:id), incidents: { workspace_id: root.workspace_id })
                                    .includes(:incident).group_by(&:catalog_entry_id).transform_values { |values| values.map(&:incident).uniq }
      entries.map { |entry| Service.new(entry: entry, owning_teams: entry.owning_teams, open_incidents: incidents.fetch(entry.id, [])) }
    end
  end

  private

  def tally(grouped) = grouped.count.sort_by { |value, count| [ -count, value.to_s ] }.to_h
end
