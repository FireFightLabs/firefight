module Slack
  module Messages
    module Resolution
      def self.build(incident, resolved_by_platform_user_id:)
        summary_text = incident.summary.present? ? "> #{incident.summary}" : "_No summary provided_"
        duration_text = Formatting.format_duration(incident.time_to_resolve)
        emoji = Formatting.severity_emoji(incident.incident_severity)

        [
          { type: "section", text: { type: "mrkdwn", text: ":white_check_mark:  *Incident Resolved*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: summary_text } },
          {
            type: "context",
            elements: [
              { type: "mrkdwn", text: "Resolved by <@#{resolved_by_platform_user_id}>  |  #{emoji} #{incident.incident_severity.name}  |  Time to resolve: #{duration_text}" }
            ]
          }
        ]
      end

      def self.announcement_thread(incident, resolved_by_platform_user_id:)
        summary_text = incident.summary.present? ? incident.summary : "_No summary provided_"
        duration_text = Formatting.format_duration(incident.time_to_resolve)
        emoji = Formatting.severity_emoji(incident.incident_severity)

        [
          { type: "header", text: { type: "plain_text", text: "Incident Resolved", emoji: true } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: summary_text } },
          { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: Resolved by: *<@#{resolved_by_platform_user_id}>*" } },
          { type: "section", text: { type: "mrkdwn", text: "#{emoji} Severity: *#{incident.incident_severity.name}*" } },
          { type: "section", text: { type: "mrkdwn", text: ":stopwatch: Time to resolve: *#{duration_text}*" } }
        ]
      end
    end
  end
end
