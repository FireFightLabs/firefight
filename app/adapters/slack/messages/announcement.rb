module Slack
  module Messages
    # `build_from` takes a plain hash for the install-time preview, when there
    # is no incident yet.
    module Announcement
      def self.build(incident)
        blocks = IncidentDetail.for_incident(incident, channel_id: incident.channel_id)
        blocks + footer(Slack::DashboardUrl.incident(incident), incident_id: incident.id)
      end

      def self.build_from(title:, summary:, severity_name:, status_name:, type_name: nil, reporter_id:, lead_id: nil, channel_id: nil, relationship_text: nil, custom_fields_text: nil, homepage_url: nil)
        IncidentDetail.blocks(
          title: title, summary: summary, severity_name: severity_name, status_name: status_name,
          reporter_id: reporter_id, lead_id: lead_id, channel_id: channel_id,
          relationship_text: relationship_text, custom_fields_text: custom_fields_text
        ) + footer(homepage_url, incident_id: nil)
      end

      # The preview has no incident to subscribe to, so its button is inert.
      def self.footer(homepage_url, incident_id:)
        homepage_button = {
          type: "button",
          text: { type: "plain_text", text: ":globe_with_meridians: Incident homepage", emoji: true },
          action_id: homepage_url ? Identifiers::INCIDENT_HOMEPAGE : Identifiers::PREVIEW_HOMEPAGE_DISABLED
        }
        homepage_button[:url] = homepage_url if homepage_url

        subscribe_button = {
          type: "button",
          text: { type: "plain_text", text: ":bell: Subscribe", emoji: true },
          action_id: incident_id ? Identifiers::SUBSCRIBE_INCIDENT : Identifiers::PREVIEW_SUBSCRIBE_DISABLED
        }
        subscribe_button[:value] = incident_id if incident_id

        [
          { type: "divider" },
          { type: "actions", elements: [ homepage_button, subscribe_button ] }
        ]
      end
      private_class_method :footer
    end
  end
end
