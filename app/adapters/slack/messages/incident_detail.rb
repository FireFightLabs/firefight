module Slack
  module Messages
    # What the announcement, the pinned message and a subscriber's direct message say about an incident, kept in one
    # place so they never drift. Each says it once: the title, then one state line, never a section per field.
    module IncidentDetail
      TEST_NOTE = "#{Slack::Emoji::TEST} Test incident. Not counted in your metrics.".freeze
      # Between the parts of a title or a state line, which read as one phrase.
      SEPARATOR = " · ".freeze

      # Used for the fallback text too, so notifications match the title.
      def self.title_for(incident)
        "#{incident.identifier}#{SEPARATOR}#{incident.name || 'Untitled incident'}"
      end

      # "Minor · Investigating · Lead @Dana", the incident's state on one line.
      def self.state_line(severity_name:, status_name:, lead_id: nil, lead_name: nil)
        parts = [ severity_name, status_name ]
        parts << "Lead #{Mrkdwn.person(lead_id, lead_name)}" if lead_id.present? || lead_name.present?
        parts.join(SEPARATOR)
      end

      def self.state_line_for(incident)
        state_line(severity_name: incident.incident_severity.name, status_name: incident.incident_status.name,
                   lead_id: incident.lead&.platform_user_id, lead_name: incident.lead&.actor_display_name)
      end

      def self.declared_by_line(incident)
        "Declared by #{Mrkdwn.person(incident.declared_by&.platform_user_id, incident.declared_by&.actor_display_name)}"
      end

      # Custom fields and links to other incidents, which only some incidents have, after the title and state.
      def self.extra_blocks(incident)
        [ Formatting.custom_fields_summary(incident), Formatting.relationship_summary(incident) ].compact.map do |text|
          { type: "section", text: { type: "mrkdwn", text: text } }
        end
      end

      def self.join_channel_button(incident, label: "Join channel")
        {
          type: "button",
          text: { type: "plain_text", text: label, emoji: true },
          url: "https://slack.com/app_redirect?team=#{incident.workspace.platform_id}&channel=#{incident.channel_id}",
          action_id: Identifiers::OPEN_INCIDENT_CHANNEL
        }
      end

      # The preview has no incident, so its buttons are inert.
      def self.homepage_button(homepage_url)
        button = {
          type: "button",
          text: { type: "plain_text", text: "Open in Firefight", emoji: true },
          action_id: homepage_url ? Identifiers::INCIDENT_HOMEPAGE : Identifiers::PREVIEW_HOMEPAGE_DISABLED
        }
        button[:url] = homepage_url if homepage_url
        button
      end

      def self.subscribe_button(incident_id)
        button = {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::SUBSCRIBE} Subscribe", emoji: true },
          action_id: incident_id ? Identifiers::SUBSCRIBE_INCIDENT : Identifiers::PREVIEW_SUBSCRIBE_DISABLED
        }
        button[:value] = incident_id if incident_id
        button
      end
    end
  end
end
