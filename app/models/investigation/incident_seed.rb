# Reads Firefight's own tables only. No provider call, no model call.
class Investigation::IncidentSeed
  ALERT_LIMIT = 10
  RUNBOOK_LIMIT = 5
  PAST_INCIDENT_LIMIT = 3

  def initialize(investigation)
    @investigation = investigation
    @incident = investigation.subject
  end

  def gather
    alerts = seed_alerts
    map = Investigation::MapFacts.new(@investigation, @incident, Investigation::Clues.new(@investigation).gather)
    resources = map.resources
    {
      Investigation::Seeding::KEY_GATHERED_AT => Time.current.iso8601,
      "incident" => incident_facts,
      "alerts" => alerts.map { |alert| alert_facts(alert) },
      "alerts_held_back" => [ @incident.alerts.count - alerts.size, 0 ].max,
      "runbooks" => runbook_facts,
      "past_incidents" => past_incident_facts(alerts),
      "services" => service_facts,
      "resources" => resources.presence,
      "resources_held_back" => (map.held_back if resources.any?),
      "brief" => @investigation.brief.presence,
      Investigation::Seeding::KEY_ON_CALL => (on_call_facts if @investigation.started_by_alert?)
    }.compact
  end

  private

  # An alert started the run and nobody asked, so the run is told what the team allowed ahead: the changes it may make
  # on its own and when, and whether it pages whoever is on call.
  def on_call_facts
    workspace = @investigation.workspace
    rules = workspace.unattended_rules.enabled.includes(:resource).select { |rule| rule.blocked_reason.nil? }
    {
      "started_from" => "An alert opened this incident and started this run. Nobody asked, and nobody may be watching yet.",
      "unattended_rules" => rules.map { |rule| { "rule" => rule.sentence, "fix_step" => { "tool" => rule.spec.tool_name, "resource" => rule.resource.name } } },
      "pages_on_call" => workspace.on_call_paging_enabled?
    }
  end

  def seed_alerts
    @incident.alerts.includes(:alert_source).order(received_at: :asc).first(ALERT_LIMIT)
  end

  def incident_facts
    {
      "identifier" => @incident.identifier,
      "name" => @incident.name,
      "summary" => @incident.summary,
      "severity" => @incident.incident_severity.name,
      "status" => @incident.incident_status.name,
      "type" => @incident.incident_type&.name,
      "declared_at" => @incident.declared_at&.iso8601,
      "detected_at" => @incident.detected_at&.iso8601,
      "lead" => person_facts(@incident.lead),
      "roles" => role_facts,
      "directs_halon" => directing_facts
    }
  end

  # Whose direction the run follows when responders' notes conflict, as the handbook names it.
  def directing_facts
    role = Chat::HandbookPage.directing_role(@incident.workspace)
    return nil unless role

    { "role" => role.name, "member" => person_facts(@incident.role_holder(role)) }
  end

  # Sorted by role position so the order matches the dashboard.
  def role_facts
    assignments = @incident.incident_role_assignments.includes(:incident_role, :workspace_membership)
    assignments.sort_by { |assignment| assignment.incident_role.position }.filter_map do |assignment|
      next if assignment.incident_role.system?

      { "role" => assignment.incident_role.name, "member" => person_facts(assignment.workspace_membership) }
    end
  end

  # No platform id. The engine reads this pack, and a Slack user id means nothing to it.
  def person_facts(membership)
    return nil unless membership

    { "name" => membership.display_name }
  end

  # The provider's payload, kept whole because the agent reads it.
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

  # The services named on the incident, and where each keeps its code, so the run knows which repositories to read.
  def service_facts
    @incident.catalog_services.map { |entry| { "name" => entry.name, "repository" => entry.repository } }
  end

  def runbook_facts
    @incident.incident_runbooks.includes(:runbook).first(RUNBOOK_LIMIT).map do |attachment|
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
        **past_answer(past)
      }
    end
  end

  NOT_RATED = "not rated".freeze

  # The answer a past incident's run gave, with what the team said of it, so a wrong one is read as a mistake to avoid
  # and a confirmed one as a worked example. A confirmed answer is preferred.
  def past_answer(past)
    found = past.investigations.reject(&:rehearsal?).sort_by(&:created_at).filter_map(&:finding).select { |finding| finding.summary.present? }
    answer = found.find { |finding| finding.outcome == Investigation::Finding::OUTCOME_CONFIRMED } || found.first
    return {} unless answer

    { "finding" => answer.summary, "finding_outcome" => answer.outcome || NOT_RATED }
  end

  def past_incidents(alerts)
    matching = alerts.map { |alert| Alert.where(alert_source_id: alert.alert_source_id, fingerprint: alert.fingerprint) }
                     .reduce(:or)
    incident_ids = matching.where(workspace_id: @investigation.workspace_id)
                           .where.not(incident_id: [ nil, @incident.id ])
                           .distinct.pluck(:incident_id)
    return [] if incident_ids.empty?

    @investigation.workspace.incidents.where(id: incident_ids, deleted_at: nil).real
                  .where.not(resolved_at: nil)
                  .includes(investigations: :finding)
                  .order(resolved_at: :desc).limit(PAST_INCIDENT_LIMIT)
  end
end
