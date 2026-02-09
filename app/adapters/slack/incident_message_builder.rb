module Slack
  class IncidentMessageBuilder
    # Quick actions message posted and pinned in incident channel
    def self.quick_actions_blocks(incident)
      [
        {
          type: "header",
          text: {
            type: "plain_text",
            text: "#{incident.identifier}: #{incident.name || 'Untitled Incident'}"
          }
        },
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: [
              "*Severity:* #{severity_emoji(incident.incident_severity)} #{incident.incident_severity.name}",
              "*Status:* #{incident.incident_status.name}",
              "*Declared by:* <@#{incident.declared_by.platform_user_id}>"
            ].join("\n")
          }
        },
        { type: "divider" },
        {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "Make me Lead" },
              action_id: "set_incident_lead_self",
              value: incident.id
            },
            {
              type: "button",
              text: { type: "plain_text", text: "Update summary" },
              action_id: "update_incident_summary",
              value: incident.id
            }
          ]
        }
      ]
    end

    # Announcement posted to #incidents channel
    def self.announcement_blocks(incident)
      [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: [
              "*New incident declared*",
              "",
              "*#{incident.identifier}* #{incident.name || 'Untitled Incident'}",
              "*Severity:* #{severity_emoji(incident.incident_severity)} #{incident.incident_severity.name} | *Status:* #{incident.incident_status.name}",
              "",
              "Declared by: <@#{incident.declared_by.platform_user_id}>",
              "Channel: <##{incident.slack_channel_id}>"
            ].join("\n")
          }
        }
      ]
    end

    def self.severity_emoji(severity)
      case severity.slug
      when "critical" then ":red_circle:"
      when "major" then ":large_yellow_circle:"
      when "minor" then ":large_green_circle:"
      else ":white_circle:"
      end
    end
  end
end
