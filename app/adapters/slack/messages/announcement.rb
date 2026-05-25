module Slack
  module Messages
    # Announcement posted to the #incidents channel when an incident is
    # declared. `build` derives the message from an Incident; `build_from`
    # accepts a plain hash and is used for the install-time preview when
    # there's no real incident yet.
    module Announcement
      def self.build(incident)
        base_url = ENV["APP_URL"]
        homepage_url = base_url ? "#{base_url}/app/incidents/#{incident.id}" : nil

        build_from(
          title: "#{incident.identifier} · #{incident.name || 'Untitled Incident'}",
          summary: incident.summary,
          severity_name: incident.incident_severity.name,
          status_name: incident.incident_status.name,
          type_name: incident.incident_type&.name,
          reporter_id: incident.declared_by.platform_user_id,
          lead_id: incident.lead&.platform_user_id,
          channel_id: incident.channel_id,
          relationship_text: Formatting.relationship_summary(incident),
          custom_fields_text: Formatting.custom_fields_summary(incident),
          homepage_url: homepage_url
        )
      end

      def self.build_from(title:, summary:, severity_name:, status_name:, type_name: nil, reporter_id:, lead_id: nil, channel_id: nil, relationship_text: nil, custom_fields_text: nil, homepage_url: nil)
        blocks = [
          { type: "header", text: { type: "plain_text", text: ":rotating_light: #{title}", emoji: true } }
        ]

        blocks << { type: "section", text: { type: "mrkdwn", text: "_#{summary}_" } } if summary.present?

        blocks << { type: "divider" }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":fire: *Severity:* #{severity_name}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":construction: *Status:* #{status_name}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{lead_id}>" } } if lead_id
        blocks << { type: "section", text: { type: "mrkdwn", text: ":mega: *Reporter:* <@#{reporter_id}>" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":speech_balloon: *Channel:* <##{channel_id}>" } } if channel_id
        blocks << { type: "section", text: { type: "mrkdwn", text: custom_fields_text } } if custom_fields_text
        blocks << { type: "section", text: { type: "mrkdwn", text: relationship_text } } if relationship_text
        blocks << { type: "divider" }

        homepage_button = {
          type: "button",
          text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
          action_id: homepage_url ? Identifiers::INCIDENT_HOMEPAGE : Identifiers::PREVIEW_HOMEPAGE_DISABLED
        }
        homepage_button[:url] = homepage_url if homepage_url

        blocks << {
          type: "actions",
          elements: [
            homepage_button,
            {
              type: "button",
              text: { type: "plain_text", text: ":bell: Subscribe", emoji: true },
              action_id: Identifiers::PREVIEW_SUBSCRIBE_DISABLED
            }
          ]
        }

        blocks
      end
    end
  end
end
