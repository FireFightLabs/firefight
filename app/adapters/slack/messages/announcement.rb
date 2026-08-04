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

        blocks = IncidentDetail.for_incident(incident, channel_id: incident.channel_id)
        blocks + footer(homepage_url)
      end

      def self.build_from(title:, summary:, severity_name:, status_name:, type_name: nil, reporter_id:, lead_id: nil, channel_id: nil, relationship_text: nil, custom_fields_text: nil, homepage_url: nil)
        IncidentDetail.blocks(
          title: title, summary: summary, severity_name: severity_name, status_name: status_name,
          reporter_id: reporter_id, lead_id: lead_id, channel_id: channel_id,
          relationship_text: relationship_text, custom_fields_text: custom_fields_text
        ) + footer(homepage_url)
      end

      def self.footer(homepage_url)
        homepage_button = {
          type: "button",
          text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
          action_id: homepage_url ? Identifiers::INCIDENT_HOMEPAGE : Identifiers::PREVIEW_HOMEPAGE_DISABLED
        }
        homepage_button[:url] = homepage_url if homepage_url

        [
          { type: "divider" },
          {
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
        ]
      end
      private_class_method :footer
    end
  end
end
