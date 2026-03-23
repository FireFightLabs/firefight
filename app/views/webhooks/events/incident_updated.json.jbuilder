json.partial! "webhooks/shared/envelope"

json.data do
  json.incident do
    json.partial! "webhooks/shared/incident", incident: @event.incident
  end

  json.changed_fields @event.changed_fields

  if @event.before_snapshot.present? && @event.after_snapshot.present?
    json.changes do
      @event.changed_fields.each do |field|
        json.set! field do
          json.before @event.before_snapshot[field]
          json.after @event.after_snapshot[field]
        end
      end
    end
  else
    json.changes({})
  end

  if @event.user
    json.actor do
      json.partial! "webhooks/shared/actor", actor: @event.user
    end
  else
    json.actor nil
  end
end
