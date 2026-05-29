class DomainEvent
  attr_reader :event_id, :event_type, :incident_id, :actor_type, :actor_id, :data, :occurred_at

  def initialize(event_id: nil, event_type:, incident_id:, actor_type: nil, actor_id: nil, data: {}, occurred_at:)
    @event_id = event_id
    @event_type = event_type
    @incident_id = incident_id
    @actor_type = actor_type
    @actor_id = actor_id
    @data = data
    @occurred_at = occurred_at
  end

  def incident
    @incident ||= Incident.find(incident_id)
  end

  def actor
    return @actor if defined?(@actor)
    @actor = (actor_type.constantize.find_by(id: actor_id) if actor_type && actor_id)
  end

  def incident_event
    @incident_event ||= IncidentEvent.find(event_id) if event_id
  end

  def to_h
    {
      "event_id" => event_id,
      "event_type" => event_type,
      "incident_id" => incident_id,
      "actor_type" => actor_type,
      "actor_id" => actor_id,
      "data" => data,
      "occurred_at" => occurred_at.iso8601(6)
    }
  end

  def self.from_h(hash)
    new(
      event_id: hash["event_id"],
      event_type: hash["event_type"],
      incident_id: hash["incident_id"],
      actor_type: hash["actor_type"],
      actor_id: hash["actor_id"],
      data: hash["data"] || {},
      occurred_at: Time.zone.parse(hash["occurred_at"])
    )
  end
end
