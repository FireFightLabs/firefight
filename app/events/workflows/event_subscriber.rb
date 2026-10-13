# Tells the workspace's workflows what happened to an incident: declared, changed (its status, severity, type, lead,
# roles or fields, accepted, resolved, reopened, cancelled or escalated), or a follow up or postmortem that changed.
# Each is heard once per timeline event, which is the key its runs start under.
class Workflows::EventSubscriber
  def self.handle(event)
    record = event.incident_event
    return unless record

    workspace = record.incident.workspace
    actor = record.actor
    if record.event_type == IncidentEvent::INCIDENT_CREATED
      fire(workspace, Workflow::Trigger::KIND_INCIDENT_DECLARED, record, [], actor)
    end
    changes = Workflow::Trigger::Changes.incident(record)
    fire(workspace, Workflow::Trigger::KIND_INCIDENT_CHANGED, record, changes, actor) if changes.any?
    follow_up = Workflow::Trigger::Changes.follow_up(record)
    fire(workspace, Workflow::Trigger::KIND_FOLLOW_UP_CHANGED, record, [ follow_up ], actor) if follow_up
  end

  def self.fire(workspace, kind, record, tags, actor)
    Workflow::Trigger::Events.fire!(workspace, kind, key: record.id, subject: record, details: { "tags" => tags }, actor: actor)
  end
end
