module Slack
  module Messages
    module StatusUpdate
      SECTION_TEXT_LIMIT = 3000

      def self.build(incident, message:, updated_by_platform_user_id:, scope:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
        field_lines = [
          Formatting.diff_text("Severity", previous_severity_name, incident.incident_severity.name),
          Formatting.diff_text("Status", previous_status_name, incident.incident_status.name)
        ]
        type_text = Formatting.type_diff_text(previous_type_name, incident.incident_type&.name)
        field_lines << type_text if type_text

        # A cancellation ends the incident, so it must not read as an update
        # and takes the header block Resolved and Reopened use.
        canceled = incident.canceled?
        icon = canceled ? ":wastebasket:" : ":memo:"
        noun = canceled ? "Incident canceled" : "Incident updated"

        blocks = if canceled && scope == :announcement
          [ { type: "header", text: { type: "plain_text", text: "#{icon} #{noun}", emoji: true } } ]
        else
          title = scope == :inline ? "#{incident.identifier} — #{noun}" : noun
          [ { type: "section", text: { type: "mrkdwn", text: "#{icon}  *#{title}*" } } ]
        end

        blocks << { type: "divider" }
        body_sections(message).each { |text| blocks << { type: "section", text: { type: "mrkdwn", text: text } } } if message.present?
        blocks << { type: "section", text: { type: "mrkdwn", text: field_lines.join("  ·  ") } }
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: context_text(incident, updated_by_platform_user_id, updated_by_name) } ] }

        blocks
      end

      # Quoting adds two characters a line, so a long update runs on into another section rather than failing the post.
      def self.body_sections(message)
        sections = Formatting.quoted_markdown(message).each_line.each_with_object([ +"" ]) do |line, built|
          built << +"" if built.last.present? && built.last.length + line.length > SECTION_TEXT_LIMIT
          built.last << line
        end
        sections.map { |section| section.chomp.truncate(SECTION_TEXT_LIMIT) }
      end

      def self.context_text(incident, updated_by_platform_user_id, updated_by_name = nil)
        verb = incident.canceled? ? "Canceled" : "Updated"
        parts = [ "#{verb} by #{Mrkdwn.person(updated_by_platform_user_id, updated_by_name)}" ]
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
