# Everything the map page shows for one workspace, read in a fixed number of queries whatever the map's size. What
# lights a resource up comes from the catalog: an incident names catalog services, and an entry points at the
# resources it runs on.
class ResourceMap::View
  INCIDENT_WINDOW = 30.days
  CHANGE_WINDOW = 24.hours

  Row = Data.define(:resource, :entries, :open_incidents, :recent_incident_count, :last_change, :dependent_ids, :suggested_dependent_ids,
                    :memories, :instructions, :past_incidents)

  attr_reader :workspace

  def initialize(workspace)
    @workspace = workspace
  end

  def rows
    @rows ||= resources.map do |resource|
      entries = entries_by_resource.fetch(resource.id, [])
      Row.new(
        resource: resource, entries: entries,
        open_incidents: entries.flat_map { |entry| open_incidents_by_entry.fetch(entry.id, []) }.uniq,
        recent_incident_count: entries.flat_map { |entry| recent_incident_ids_by_entry.fetch(entry.id, []) }.uniq.size,
        last_change: last_changes[resource.id], dependent_ids: dependents.fetch(resource.id, []),
        suggested_dependent_ids: suggested_dependents.fetch(resource.id, []) - dependents.fetch(resource.id, []),
        memories: ([ resource ] + entries).flat_map { |subject| memories_by_subject.fetch([ subject.class.name, subject.id ], []) },
        instructions: ([ resource ] + entries).flat_map { |subject| instructions_by_subject.fetch([ subject.class.name, subject.id ], []) },
        past_incidents: entries.flat_map { |entry| past_incidents_by_entry.fetch(entry.id, []) }.uniq
                               .sort_by(&:ended_at).reverse.first(Incident::Outcome::PAST_SHOWN)
      )
    end
  end

  def links
    @links ||= ResourceMap::Link.standing.where(workspace: workspace, from_resource_id: resource_ids, to_resource_id: resource_ids)
                                .includes(integration_environment: :integration).to_a
  end

  def changes
    ResourceMap::Change.where(workspace: workspace).since(CHANGE_WINDOW.ago).newest_first.includes(:resource).limit(50)
  end

  def connections
    IntegrationEnvironment.joins(:integration).merge(Integration.active).where(integrations: { workspace_id: workspace.id })
                          .includes(:integration).select { |row| row.map_swept_at || row.map_error }
  end

  # Who depends on a resource, directly or through others, read along each link from the one that depends to the one it
  # depends on. The count ranks what a failure would reach, so only facts count. What would also stop if the
  # suggestions are right is kept apart.
  def dependents = @dependents ||= reach(links.reject(&:unconfirmed?))

  def suggested_dependents = @suggested_dependents ||= reach(links)

  private

  def reach(through)
    needed_by = through.group_by(&:to_resource_id).transform_values { |found| found.map(&:from_resource_id) }
    resource_ids.index_with do |id|
      seen = Set.new
      queue = needed_by.fetch(id, []).dup
      until queue.empty?
        next_id = queue.shift
        next if next_id == id || !seen.add?(next_id)

        queue.concat(needed_by.fetch(next_id, []))
      end
      seen.to_a
    end
  end

  def resources
    @resources ||= ResourceMap::Resource.present.where(workspace: workspace)
                                        .includes(integration_environment: %i[integration environment]).order(:provider, :account, :name).to_a
  end

  def resource_ids = @resource_ids ||= resources.map(&:id)

  def entries_by_resource
    @entries_by_resource ||= ResourceMap::EntryLink.where(resource_id: resource_ids)
                                                   .includes(catalog_entry: [ :catalog_type, { outgoing_relationships: { target_entry: :catalog_type } } ]).to_a
                                                   .reject { |link| link.catalog_entry.deleted_at }
                                                   .group_by(&:resource_id).transform_values { |found| found.map(&:catalog_entry) }
  end

  def entry_ids = entries_by_resource.values.flatten.map(&:id).uniq

  def open_incidents_by_entry
    @open_incidents_by_entry ||= IncidentFieldValue.joins(:incident).merge(Incident.active)
                                                   .where(catalog_entry_id: entry_ids, incidents: { workspace_id: workspace.id })
                                                   .includes(:incident).group_by(&:catalog_entry_id)
                                                   .transform_values { |values| values.map(&:incident).uniq }
  end

  def past_incidents_by_entry
    @past_incidents_by_entry ||= Incident.past_on(workspace, entry_ids).group_by(&:catalog_entry_id)
                                         .transform_values { |values| values.map(&:incident).uniq }
  end

  def recent_incident_ids_by_entry
    @recent_incident_ids_by_entry ||= IncidentFieldValue.joins(:incident)
                                                        .where(catalog_entry_id: entry_ids, incidents: { workspace_id: workspace.id, created_at: INCIDENT_WINDOW.ago.. })
                                                        .pluck(:catalog_entry_id, :incident_id)
                                                        .group_by(&:first).transform_values { |pairs| pairs.map(&:last).uniq }
  end

  # What the workspace remembers about each resource and the catalog entries it runs, in use or flagged, never rejected.
  def memories_by_subject
    @memories_by_subject ||= Chat::Memory.where(workspace: workspace, state: Chat::Memory::USED_STATES + [ Chat::Memory::STATE_DISPUTED ])
                                         .where(subject_id: resource_ids + entry_ids).most_trusted_first.to_a
                                         .group_by { |memory| [ memory.subject_type, memory.subject_id ] }
  end

  def instructions_by_subject
    @instructions_by_subject ||= Chat::Instruction.preload_labels(Chat::Instruction.current.where(workspace: workspace, scope_id: resource_ids + entry_ids).includes(:scope).to_a)
                                                  .group_by { |note| [ note.scope_type, note.scope_id ] }
  end

  def last_changes
    @last_changes ||= ResourceMap::Change.where(resource_id: resource_ids)
                                         .select("DISTINCT ON (resource_id) resource_map_changes.*")
                                         .order(:resource_id, happened_at: :desc).index_by(&:resource_id)
  end
end
