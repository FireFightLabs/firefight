module Investigation::Seeding
  extend ActiveSupport::Concern

  ALERT_LIMIT = 10
  RUNBOOK_LIMIT = 5
  PAST_INCIDENT_LIMIT = 3

  # Gathered once and stored, so every later turn reads one row and every turn
  # sees the same facts.
  def build_seed_pack!
    update!(seed_pack: gathered_facts)
    seed_pack
  end

  private

  def gathered_facts
    alerts = seed_alerts
    {
      "gathered_at" => Time.current.iso8601,
      "incident" => incident_facts,
      "alerts" => alerts.map { |alert| alert_facts(alert) },
      "alerts_held_back" => [ incident.alerts.count - alerts.size, 0 ].max,
      "runbooks" => runbook_facts,
      "past_incidents" => past_incident_facts(alerts)
    }
  end

  def seed_alerts
    incident.alerts.includes(:alert_source).order(received_at: :asc).first(ALERT_LIMIT)
  end

  def incident_facts
    {
      "identifier" => incident.identifier,
      "name" => incident.name,
      "summary" => incident.summary,
      "severity" => incident.incident_severity.name,
      "status" => incident.incident_status.name,
      "type" => incident.incident_type&.name,
      "declared_at" => incident.declared_at&.iso8601,
      "detected_at" => incident.detected_at&.iso8601,
      "lead" => person_facts(incident.lead),
      "roles" => role_facts
    }
  end

  # Ordered by the role's own position, so the pack and the dashboard list them the same way.
  def role_facts
    assignments = incident.incident_role_assignments.includes(:incident_role, :workspace_membership)
    assignments.sort_by { |assignment| assignment.incident_role.position }.filter_map do |assignment|
      next if assignment.incident_role.system?

      { "role" => assignment.incident_role.name, "member" => person_facts(assignment.workspace_membership) }
    end
  end

  def person_facts(membership)
    return nil unless membership

    { "name" => membership.display_name, "platform_user_id" => membership.platform_user_id }
  end

  # Fields are the provider's own payload, kept whole because the agent reads them.
  def alert_facts(alert)
    {
      "source" => alert.alert_source.name,
      "title" => alert.title,
      "fingerprint" => alert.fingerprint,
      "status" => alert.status,
      "received_at" => alert.received_at.iso8601,
      "last_seen_at" => alert.last_seen_at.iso8601,
      "fields" => alert.fields
    }
  end

  def runbook_facts
    incident.incident_runbooks.includes(:runbook).first(RUNBOOK_LIMIT).map do |attachment|
      { "name" => attachment.runbook.name, "summary" => attachment.runbook.summary }
    end
  end

  # A fingerprint is only unique within its source, so both have to match.
  def past_incident_facts(alerts)
    return [] if alerts.empty?

    past_incidents(alerts).map do |past|
      {
        "identifier" => past.identifier,
        "name" => past.name,
        "summary" => past.summary,
        "declared_at" => past.declared_at&.iso8601,
        "resolved_at" => past.resolved_at&.iso8601,
        "finding" => past.investigations.filter_map { |run| run.finding&.summary }.first
      }
    end
  end

  def past_incidents(alerts)
    matching = alerts.map { |alert| Alert.where(alert_source_id: alert.alert_source_id, fingerprint: alert.fingerprint) }
                     .reduce(:or)
    incident_ids = matching.where(workspace_id: workspace_id)
                           .where.not(incident_id: [ nil, incident_id ])
                           .distinct.pluck(:incident_id)
    return [] if incident_ids.empty?

    workspace.incidents.where(id: incident_ids, deleted_at: nil).real
             .where.not(resolved_at: nil)
             .includes(investigations: :finding)
             .order(resolved_at: :desc).limit(PAST_INCIDENT_LIMIT)
  end
end
