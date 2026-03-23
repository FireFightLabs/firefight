class DomainEvent
  attr_reader :event_id, :event_type, :incident_id, :user_id, :data, :occurred_at

  def initialize(event_id: nil, event_type:, incident_id:, user_id: nil, data: {}, occurred_at:)
    @event_id = event_id
    @event_type = event_type
    @incident_id = incident_id
    @user_id = user_id
    @data = data
    @occurred_at = occurred_at
  end

  def incident
    @incident ||= Incident.find(incident_id)
  end

  def user
    @user ||= WorkspaceMembership.find(user_id) if user_id
  end

  def incident_event
    @incident_event ||= IncidentEvent.find(event_id) if event_id
  end

  def to_h
    {
      "event_id" => event_id,
      "event_type" => event_type,
      "incident_id" => incident_id,
      "user_id" => user_id,
      "data" => data,
      "occurred_at" => occurred_at.iso8601(6)
    }
  end

  def self.from_h(hash)
    new(
      event_id: hash["event_id"],
      event_type: hash["event_type"],
      incident_id: hash["incident_id"],
      user_id: hash["user_id"],
      data: hash["data"] || {},
      occurred_at: Time.zone.parse(hash["occurred_at"])
    )
  end
end
