# The facts for a question nobody has declared an incident for. It could be about anything the workspace runs, so it
# holds what is open, what fired lately and every service with where its code lives. Firefight's own tables only.
class Investigation::QuestionSeed
  INCIDENT_LIMIT = 10
  ALERT_LIMIT = 10
  ALERT_WINDOW = 24.hours
  SERVICE_LIMIT = 50

  def initialize(investigation)
    @investigation = investigation
    @workspace = investigation.workspace
  end

  def gather
    alerts = recent_alerts
    {
      Investigation::Seeding::KEY_GATHERED_AT => Time.current.iso8601,
      "question" => @investigation.question,
      "brief" => @investigation.brief.presence,
      "open_incidents" => open_incident_facts,
      "recent_alerts" => alerts.map { |alert| alert_facts(alert) },
      "services" => service_facts
    }.compact
  end

  private

  def open_incident_facts
    @workspace.incidents.active.real.where(deleted_at: nil).includes(:incident_severity, :incident_status)
              .order(declared_at: :desc).limit(INCIDENT_LIMIT).map do |incident|
      {
        "identifier" => incident.identifier,
        "name" => incident.name,
        "severity" => incident.incident_severity.name,
        "status" => incident.incident_status.name,
        "declared_at" => incident.declared_at&.iso8601
      }
    end
  end

  def recent_alerts
    @workspace.alerts.includes(:alert_source, :incident).where(received_at: ALERT_WINDOW.ago..)
              .order(received_at: :desc).limit(ALERT_LIMIT).to_a
  end

  # The provider's payload, kept whole because the agent reads it.
  def alert_facts(alert)
    {
      "source" => alert.alert_source.name,
      "title" => alert.title,
      "status" => alert.status,
      "received_at" => alert.received_at.iso8601,
      "incident" => alert.incident&.identifier,
      "fields" => alert.fields
    }.compact
  end

  def service_facts
    @workspace.catalog_entries.in_system_type([ CatalogType::SYSTEM_KEY_SERVICE ])
              .includes(catalog_type: :catalog_attribute_definitions).ordered.limit(SERVICE_LIMIT)
              .map { |entry| { "name" => entry.name, "repository" => entry.repository }.compact }
  end
end
