module Slack
  class IncidentTimelineFormatter
    EVENT_STYLE = {
      IncidentEvent::INCIDENT_CREATED => { emoji: ":rotating_light:", title: "Incident declared" },
      IncidentEvent::INCIDENT_UPDATED => { emoji: ":memo:", title: "Incident updated" },
      IncidentEvent::INCIDENT_ACCEPTED => { emoji: ":white_check_mark:", title: "Incident accepted" },
      IncidentEvent::LEAD_ASSIGNED => { emoji: ":firefighter:", title: "Lead assigned" },
      IncidentEvent::INCIDENT_ESCALATED => { emoji: ":rotating_light:", title: "Incident escalated" },
      IncidentEvent::INCIDENT_RESOLVED => { emoji: ":white_check_mark:", title: "Incident resolved" },
      IncidentEvent::INCIDENT_REOPENED => { emoji: ":warning:", title: "Incident reopened" },
      IncidentEvent::RELATIONSHIP_CREATED => { emoji: ":link:", title: "Incident linked" },
      IncidentEvent::MARKED_DUPLICATE => { emoji: ":repeat:", title: "Marked duplicate" },
      IncidentEvent::MERGED_INTO => { emoji: ":repeat:", title: "Merged into incident" },
      IncidentEvent::ACTION_CREATED => { emoji: ":clipboard:", title: "Action created" },
      IncidentEvent::ACTION_PICKED_UP => { emoji: ":raised_hands:", title: "Action picked up" },
      IncidentEvent::ACTION_COMPLETED => { emoji: ":white_check_mark:", title: "Action completed" },
      IncidentEvent::POSTMORTEM_GENERATED => { emoji: ":scroll:", title: "Postmortem generated" },
      IncidentEvent::POSTMORTEM_EDITED => { emoji: ":pencil2:", title: "Postmortem edited" },
      IncidentEvent::MESSAGE_PINNED => { emoji: ":pushpin:", title: "Message pinned" },
      IncidentEvent::MESSAGE_UNPINNED => { emoji: ":round_pushpin:", title: "Message unpinned" },
      IncidentEvent::MESSAGE_FILE_SHARED => { emoji: ":paperclip:", title: "File shared" },
      IncidentEvent::ESCALATION_ACKNOWLEDGED => { emoji: ":white_check_mark:", title: "Escalation acknowledged" },
      IncidentEvent::ESCALATION_NUDGED => { emoji: ":bell:", title: "Escalation reminder sent" }
    }.freeze

    def self.label_for(event)
      EVENT_STYLE.dig(event.event_type, :title) || event.description || event.event_type
    end
    private_class_method :label_for

    def self.emoji_for(event)
      EVENT_STYLE.dig(event.event_type, :emoji) || ":small_blue_diamond:"
    end
    private_class_method :emoji_for

    def self.actor_mention_for(event)
      user_id = (event.metadata || {})["user_id"] || event.actor&.platform_user_id
      user_id.present? ? "<@#{user_id}>" : "System"
    end
    private_class_method :actor_mention_for

    def self.to_block(event)
      details = details_for(event)
      actor = actor_mention_for(event)

      section_text = "#{emoji_for(event)} *#{label_for(event)}*"
      section_text += "\n#{details}" if details.present?

      unix_ts = event.created_at.to_i
      fallback = event.created_at.in_time_zone.strftime("%Y-%m-%d %H:%M")
      context_text = "<!date^#{unix_ts}^{date_short_pretty} at {time}|#{fallback}> · #{actor}"

      {
        section: {
          type: "section",
          text: { type: "mrkdwn", text: section_text }
        },
        context: {
          type: "context",
          elements: [ { type: "mrkdwn", text: context_text } ]
        }
      }
    end

    def self.to_blocks(events)
      events.flat_map do |event|
        block = to_block(event)
        [ block[:section], block[:context] ]
      end
    end

    def self.details_for(event)
      details = event.metadata || {}

      case event.event_type
      when IncidentEvent::INCIDENT_ESCALATED
        target = details["escalated_to_platform_user_id"]
        reason = details["reason"]
        detail = target.present? ? "to <@#{target}>" : nil
        [ detail, reason ].compact.join(" | ")
      when IncidentEvent::MESSAGE_PINNED, IncidentEvent::MESSAGE_UNPINNED
        details["permalink"].presence
      when IncidentEvent::MESSAGE_FILE_SHARED
        file_name = details["file_name"]
        permalink = details["permalink"].present? ? "<#{details['permalink']}|Open in Slack>" : nil
        [ file_name, permalink ].compact.join(" · ")
      when IncidentEvent::INCIDENT_REOPENED
        details["reason"]
      when IncidentEvent::ESCALATION_ACKNOWLEDGED
        "by <@#{details['acknowledged_by_platform_user_id']}>"
      when IncidentEvent::ESCALATION_NUDGED
        "to <@#{details['escalated_to_platform_user_id']}>"
      else
        eventable = event.eventable
        message = if eventable&.respond_to?(:message)
          eventable.message
        elsif eventable&.respond_to?(:description)
          eventable.description
        end

        message.presence || details["reason"]
      end
    end
    private_class_method :details_for
  end
end
