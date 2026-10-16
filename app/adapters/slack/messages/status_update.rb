module Slack
  module Messages
    # An incident update as a card: the title, what changed as its subtitle, and the update as its body, with who wrote it
    # and when the next one is due under it. A cancellation ends the incident, so it never reads as an update.
    module StatusUpdate
      def self.build(incident, message:, updated_by_platform_user_id:, scope:, rich:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
        canceled = incident.canceled?
        noun = canceled ? "Incident canceled" : "Incident updated"
        title = scope == :inline ? "#{incident.identifier}#{IncidentDetail::SEPARATOR}#{noun}" : noun

        card = Slack::Blocks::Card.new(
          title: title,
          subtitle: change_line(incident, previous_status_name, previous_severity_name, previous_type_name),
          body: (Formatting.markdown_to_mrkdwn(message) if message.present?),
          icon: canceled ? Slack::Emoji::CANCELED : Slack::Emoji::UPDATED,
          quoted: true
        )
        card.to_blocks(rich: rich) << Slack::Blocks.context(context_text(incident, updated_by_platform_user_id, updated_by_name))
      end

      def self.change_line(incident, previous_status_name, previous_severity_name, previous_type_name)
        lines = [
          Formatting.diff_text("Severity", previous_severity_name, incident.incident_severity.name),
          Formatting.diff_text("Status", previous_status_name, incident.incident_status.name)
        ]
        type_text = Formatting.type_diff_text(previous_type_name, incident.incident_type&.name)
        lines << type_text if type_text
        lines.join(IncidentDetail::SEPARATOR)
      end

      # What changed and who changed it, the subtitle of a subscriber's card.
      def self.digest_line(incident, updated_by_platform_user_id, updated_by_name, previous_status_name, previous_severity_name, previous_type_name)
        verb = incident.canceled? ? "Canceled" : "Updated"
        [ change_line(incident, previous_status_name, previous_severity_name, previous_type_name),
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
