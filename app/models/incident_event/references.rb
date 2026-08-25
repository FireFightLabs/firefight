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
      incidents: workspace.incidents.where(id: incident_ids).index_by(&:id)
    )
  end

  def initialize(members:, runbooks:, incidents:)
    @members = members
    @runbooks = runbooks
    @incidents = incidents
  end

  def member(id) = id && @members[id]
  def runbook(id) = id && @runbooks[id]
  def incident(id) = id && @incidents[id]
end
