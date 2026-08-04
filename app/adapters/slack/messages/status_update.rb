module Slack
  module Messages
    # Status-update messages: posted both inline in the incident channel
    # and as a thread reply on the announcement. The two variants only
    # differ in their header line, so `build` takes a `scope:` of
    # `:inline` or `:announcement`.
    module StatusUpdate
      def self.build(incident, message:, updated_by_platform_user_id:, scope:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
        field_lines = [
          Formatting.diff_text("Severity", previous_severity_name, incident.incident_severity.name),
          Formatting.diff_text("Status", previous_status_name, incident.incident_status.name)
        ]
        type_text = Formatting.type_diff_text(previous_type_name, incident.incident_type&.name)
        field_lines << type_text if type_text

        # A cancellation posts through the same path as any status change, so
        # the wording follows the stage rather than calling it an update.
        canceled = incident.canceled?
        icon = canceled ? ":wastebasket:" : ":memo:"
        noun = canceled ? "Incident canceled" : "Incident updated"

        header_text = case scope
        when :inline       then "#{icon} *#{incident.identifier} — #{noun}*"
        when :announcement then "#{icon} *#{noun}*"
        end

        blocks = [ { type: "section", text: { type: "mrkdwn", text: header_text } } ]
        blocks << { type: "section", text: { type: "mrkdwn", text: "> #{message}" } } if message.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: field_lines.join("  ·  ") } }
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: context_text(incident, updated_by_platform_user_id) } ] }

        blocks
      end

      def self.context_text(incident, updated_by_platform_user_id)
        verb = incident.canceled? ? "Canceled" : "Updated"
        parts = [ "#{verb} by <@#{updated_by_platform_user_id}>" ]
        if incident.next_update_at.present?
          unix_ts = incident.next_update_at.to_i
          fallback = incident.next_update_at.in_time_zone.strftime("%H:%M")
          parts << "Next update <!date^#{unix_ts}^{date_short_pretty} at {time}|#{fallback}>"
        end
        parts.join("  ·  ")
      end

      def self.update_reminder(incident)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":alarm_clock: It's time to provide a status update for *#{incident.identifier}*" }
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
