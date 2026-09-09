# The records an incident's events point at through metadata: members the
# incident was escalated to, who took a role, who said what an AI note quotes
# or who dismissed one, runbooks that were attached, incidents that were
# linked or merged. Loaded once per timeline so the serializer never queries
# per row.
class IncidentEvent::References
  def self.for(incident, events)
    metadata = events.map { |event| event.metadata.to_h }
    member_ids = metadata.flat_map do |meta|
      [ meta["escalated_to_member_id"], meta["member_id"], meta["dismissed_by_member_id"] ]
    end.compact.uniq
    runbook_ids = metadata.filter_map { |meta| meta["runbook_id"] }.uniq
    incident_ids = metadata.flat_map { |meta| [ meta["related_incident_id"], meta["canonical_incident_id"] ] }.compact.uniq
    workspace = incident.workspace

    new(
      members: workspace.workspace_memberships.where(id: member_ids).includes(:user).index_by(&:id),
      runbooks: workspace.runbooks.where(id: runbook_ids).index_by(&:id),
      incidents: workspace.incidents.where(id: incident_ids).index_by(&:id),
      field_definitions: field_definitions_for(workspace, events)
    )
  end

  # Only a timeline with a custom field change loads definitions at all. A
  # deleted definition still names its old changes, and when a live one has
  # reused the slug the live one wins: NULL deleted_at sorts last, so it is
  # the row index_by keeps.
  def self.field_definitions_for(workspace, events)
    updates = events.map(&:eventable).grep(IncidentUpdate)
    return {} unless updates.any? { |update| update.changed_fields.include?(IncidentUpdate::FIELD_CUSTOM_FIELDS) }

    slugs = updates.flat_map { |update| update.custom_fields.keys }.uniq
    workspace.incident_field_definitions.where(slug: slugs).order(:deleted_at).index_by(&:slug)
  end

  def initialize(members:, runbooks:, incidents:, field_definitions: {})
    @members = members
    @runbooks = runbooks
    @incidents = incidents
    @field_definitions = field_definitions
  end

  attr_reader :field_definitions

  def member(id) = id && @members[id]
  def runbook(id) = id && @runbooks[id]
  def incident(id) = id && @incidents[id]
end
