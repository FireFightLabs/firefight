module Slack
  module Messages
    # An incident update: the title, a divider, the update quoted, what changed on one line, then who wrote it and when
    # the next one is due. A cancellation ends the incident, so it never reads as an update.
    module StatusUpdate
      def self.build(incident, message:, updated_by_platform_user_id:, scope:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
        canceled = incident.canceled?
        icon = canceled ? Slack::Emoji::CANCELED : Slack::Emoji::UPDATED
        noun = canceled ? "Incident canceled" : "Incident updated"

        # A cancellation in the announcement thread takes a header block, as the end of the incident.
        blocks = if canceled && scope == :announcement
          [ { type: "header", text: { type: "plain_text", text: "#{icon} #{noun}", emoji: true } } ]
        else
          title = scope == :inline ? "#{incident.identifier}#{IncidentDetail::SEPARATOR}#{noun}" : noun
          [ Slack::Blocks.section("#{icon}  *#{title}*") ]
        end

        blocks << { type: "divider" }
        blocks.concat(Formatting.quoted_blocks(message))
        blocks << Slack::Blocks.section(changes(incident, previous_status_name, previous_severity_name, previous_type_name).join(Formatting::SEPARATOR))
        blocks << Slack::Blocks.context(context_text(incident, updated_by_platform_user_id, updated_by_name))
      end

      def self.changes(incident, previous_status_name, previous_severity_name, previous_type_name)
        [
          Formatting.diff_text("Severity", previous_severity_name, incident.incident_severity.name),
          Formatting.diff_text("Status", previous_status_name, incident.incident_status.name),
          Formatting.type_diff_text(previous_type_name, incident.incident_type&.name)
        ].compact
      end
      private_class_method :changes

      # What changed and who changed it in one line, the fallback text of a subscriber's direct message.
      def self.headline(incident, updated_by_platform_user_id, updated_by_name, previous_status_name, previous_severity_name, previous_type_name)
        verb = incident.canceled? ? "Canceled" : "Updated"
        [ *changes(incident, previous_status_name, previous_severity_name, previous_type_name),
          "#{verb} by #{Mrkdwn.person(updated_by_platform_user_id, updated_by_name)}" ].join(IncidentDetail::SEPARATOR)
      end

      def self.context_text(incident, updated_by_platform_user_id, updated_by_name = nil)
        verb = incident.canceled? ? "Canceled" : "Updated"
        parts = [ "#{verb} by #{Mrkdwn.person(updated_by_platform_user_id, updated_by_name)}" ]
        if incident.next_update_at.present?
          unix_ts = incident.next_update_at.to_i
          fallback = incident.next_update_at.in_time_zone.strftime("%H:%M")
          parts << "Next update <!date^#{unix_ts}^{date_short_pretty} at {time}|#{fallback}>"
        end
        parts.join(Formatting::SEPARATOR)
      end

      def self.update_reminder(incident)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: "#{Slack::Emoji::REMINDER} It's time to provide a status update for *#{incident.identifier}*" }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: ":writing_hand: Send an update", emoji: true },
                action_id: Identifiers::SEND_INCIDENT_UPDATE,
                value: incident.id
              }
            ]
          }
        ]
      end
    end
  end
end
