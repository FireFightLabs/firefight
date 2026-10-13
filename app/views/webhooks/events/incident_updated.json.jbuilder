json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.changed_fields @event.changed_fields

  current = @event.eventable.is_a?(IncidentUpdate) ? @event.eventable : nil
  previous = current && IncidentUpdate
    .where(incident_id: current.incident_id)
    .where("created_at < ?", current.created_at)
    .order(created_at: :desc)
    .first

  # A record renders in the same shape as on the incident above.
  record_partials = {
    IncidentUpdate::FIELD_STATUS => [ "shared/incident_status", :status ],
    IncidentUpdate::FIELD_SEVERITY => [ "shared/incident_severity", :severity ],
    IncidentUpdate::FIELD_TYPE => [ "shared/incident_type", :type ],
    IncidentUpdate::FIELD_LEAD => [ "shared/actor", :actor ],
    IncidentUpdate::FIELD_DECLARED_BY => [ "shared/actor", :actor ]
  }

  if current && @event.changed_fields.any?
    json.changes do
      @event.changed_fields.each do |field|
        partial, local = record_partials[field]
        json.set! field do
          { before: previous, after: current }.each do |moment, snapshot|
            value = snapshot&.value_for(field)
            if partial && value
              json.set!(moment) { json.partial! partial, local => value }
            else
              json.set! moment, value
            end
          end
        end
      end
    end
  else
    json.changes({})
  end

  if @event.actor
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.actor
    end
  else
    json.actor nil
  end
end
