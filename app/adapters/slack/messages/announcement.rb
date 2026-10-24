module Slack
  module Messages
    # An incident in #incidents: its details a row per field, then Join channel, Subscribe and Open in Firefight.
    # `build_from` takes a plain hash for the install-time preview, when there is no incident yet.
    module Announcement
      def self.build(incident)
        buttons = [
          (IncidentDetail.join_channel_button(incident) if incident.channel_id.present?),
          IncidentDetail.subscribe_button(incident.id),
          IncidentDetail.homepage_button(Slack::DashboardUrl.incident(incident))
        ].compact
        IncidentDetail.for_incident(incident, channel_id: incident.channel_id) + footer(buttons)
      end

      def self.build_from(title:, summary:, severity_name:, status_name:, reporter_id:, homepage_url: nil)
        IncidentDetail.blocks(title: title, summary: summary, severity_name: severity_name, status_name: status_name, reporter_id: reporter_id) +
          footer([ IncidentDetail.subscribe_button(nil), IncidentDetail.homepage_button(homepage_url) ])
      end

      def self.footer(buttons) = [ { type: "divider" }, { type: "actions", elements: buttons } ]
      private_class_method :footer
    end
  end
end
