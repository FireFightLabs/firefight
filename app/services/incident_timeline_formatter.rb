class IncidentTimelineFormatter
  def self.to_text(event)
    payload = to_h(event)
    "- #{payload[:timestamp]} #{payload[:label]}#{payload[:details].present? ? " - #{payload[:details]}" : ""}"
  end

  def self.to_h(event)
    {
      timestamp: event.created_at.in_time_zone.strftime("%Y-%m-%d %H:%M"),
      label: label_for(event),
      details: details_for(event)
    }
  end

  def self.label_for(event)
    case event.event_type
    when IncidentEvent::INCIDENT_CREATED then "Incident declared"
    when IncidentEvent::INCIDENT_UPDATED then "Incident updated"
    when IncidentEvent::LEAD_ASSIGNED then "Lead assigned"
    when IncidentEvent::INCIDENT_ESCALATED then "Incident escalated"
    when IncidentEvent::INCIDENT_RESOLVED then "Incident resolved"
    when IncidentEvent::INCIDENT_REOPENED then "Incident reopened"
    when IncidentEvent::RELATIONSHIP_CREATED then "Incident linked"
    when IncidentEvent::MARKED_DUPLICATE then "Marked duplicate"
    when IncidentEvent::MERGED_INTO then "Merged into incident"
    when IncidentEvent::ACTION_CREATED then "Action created"
    when IncidentEvent::ACTION_PICKED_UP then "Action picked up"
    when IncidentEvent::ACTION_COMPLETED then "Action completed"
    when IncidentEvent::MESSAGE_PINNED then "Message pinned"
    when IncidentEvent::MESSAGE_UNPINNED then "Message unpinned"
    when IncidentEvent::MESSAGE_FILE_SHARED then "File shared"
    else
      event.description || event.event_type
    end
  end
  private_class_method :label_for

  def self.details_for(event)
    details = event.details || {}

    case event.event_type
    when IncidentEvent::INCIDENT_ESCALATED
      target = details["escalated_to_platform_user_id"]
      reason = details["reason"]
      detail = target.present? ? "to <@#{target}>" : nil
      [ detail, reason ].compact.join(" | ")
    when IncidentEvent::MESSAGE_PINNED, IncidentEvent::MESSAGE_UNPINNED
      message_ref = details["permalink"] || details["message_ts"]
      actor = details["user_id"]
      [ (actor.present? ? "by <@#{actor}>" : nil), message_ref ].compact.join(" | ")
    when IncidentEvent::MESSAGE_FILE_SHARED
      file_name = details["file_name"]
      mime_type = details["mime_type"]
      actor = details["user_id"]
      archived = details["blob_id"].present? || details["object_key"].present?
      [ file_name, mime_type, (actor.present? ? "by <@#{actor}>" : nil), (archived ? "archived" : nil) ].compact.join(" | ")
    when IncidentEvent::INCIDENT_REOPENED
      details["reason"]
    else
      event.eventable&.message.presence || details["reason"]
    end
  end
  private_class_method :details_for
end
