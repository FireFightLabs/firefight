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
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: "#{severity_emoji(incident.incident_severity)} *Severity:* #{incident.incident_severity.name}" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: ":bar_chart: *Status:* #{incident.incident_status.name}" }
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: ":bust_in_silhouette: *Declared by:* <@#{incident.declared_by.platform_user_id}>" }
        },
        { type: "divider" },
        {
          type: "actions",
          elements: quick_action_buttons(incident)
        }
      ]
    end

    # Announcement posted to #incidents channel
    def self.announcement_blocks(incident)
      announcement_blocks_for({
        title: "#{incident.identifier}: #{incident.name || 'Untitled Incident'}",
        summary: incident.summary,
        severity_name: incident.incident_severity.name,
        severity_slug: incident.incident_severity.slug,
        status_name: incident.incident_status.name,
        reporter_id: incident.declared_by.platform_user_id,
        lead_id: incident.lead&.platform_user_id,
        channel_id: incident.channel_id
      })
    end

    # Shared announcement block builder used by both real announcements and preview
    def self.announcement_blocks_for(data)
      blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: data[:title], emoji: true }
        }
      ]

      if data[:summary].present?
        blocks << {
          type: "section",
          text: { type: "mrkdwn", text: data[:summary] }
        }
      end

      blocks << { type: "divider" }
      blocks << { type: "section", text: { type: "mrkdwn", text: "#{severity_emoji_for(data[:severity_slug])} *Severity:* #{data[:severity_name]}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bar_chart: *Status:* #{data[:status_name]}" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":bust_in_silhouette: *Reporter:* <@#{data[:reporter_id]}>" } }
      blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{data[:lead_id]}>" } } if data[:lead_id]
      blocks << { type: "section", text: { type: "mrkdwn", text: ":hash: *Channel:* <##{data[:channel_id]}>" } } if data[:channel_id]
      blocks << { type: "divider" }
      blocks << {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
            action_id: Identifiers::PREVIEW_HOMEPAGE_DISABLED,
            style: "primary"
          },
          {
            type: "button",
            text: { type: "plain_text", text: ":pushpin: Subscribe", emoji: true },
            action_id: Identifiers::PREVIEW_SUBSCRIBE_DISABLED
          }
        ]
      }

      blocks
    end

    def self.quick_action_buttons(incident)
      buttons = []

      unless incident.lead
        buttons << {
          type: "button",
          text: { type: "plain_text", text: ":firefighter: Make me Lead", emoji: true },
          action_id: Identifiers::SET_INCIDENT_LEAD_SELF,
          value: incident.id
        }
      end

      buttons << {
        type: "button",
        text: { type: "plain_text", text: ":memo: Update summary", emoji: true },
        action_id: Identifiers::UPDATE_INCIDENT_SUMMARY,
        value: incident.id
      }

      buttons
    end

    def self.severity_emoji(severity)
      severity_emoji_for(severity.slug)
    end

    def self.severity_emoji_for(slug)
      case slug
      when "critical" then ":red_circle:"
      when "major" then ":large_yellow_circle:"
      when "minor" then ":fire:"
      else ":white_circle:"
      end
    end
  end
end
