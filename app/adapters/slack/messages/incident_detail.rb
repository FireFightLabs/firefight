module Slack
  module Messages
    # The block of incident facts that both the announcement in #incidents and
    # the pinned message in the incident channel are built around. They used to
    # build it separately and had already drifted: the same person was the
    # Reporter in one and Declared by in the other.
    #
    # The channel line is the one real difference. The announcement points at
    # the incident channel; the pinned message is already in it.
    module IncidentDetail
      def self.blocks(title:, summary:, severity_name:, status_name:, reporter_id:,
                      lead_id: nil, channel_id: nil, relationship_text: nil, custom_fields_text: nil)
        blocks = [
          { type: "header", text: { type: "plain_text", text: ":rotating_light: #{title}", emoji: true } }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: "_#{summary}_" } } if summary.present?
        blocks << { type: "divider" }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":fire: *Severity:* #{severity_name}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":construction: *Status:* #{status_name}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{lead_id}>" } } if lead_id
        blocks << { type: "section", text: { type: "mrkdwn", text: ":mega: *Declared by:* <@#{reporter_id}>" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":speech_balloon: *Channel:* <##{channel_id}>" } } if channel_id
        blocks << { type: "section", text: { type: "mrkdwn", text: custom_fields_text } } if custom_fields_text
        blocks << { type: "section", text: { type: "mrkdwn", text: relationship_text } } if relationship_text
        blocks
      end

      def self.for_incident(incident, channel_id: nil)
        blocks(
          title: "#{incident.identifier} · #{incident.name || 'Untitled Incident'}",
          summary: incident.summary,
          severity_name: incident.incident_severity.name,
          status_name: incident.incident_status.name,
          reporter_id: incident.declared_by.platform_user_id,
          lead_id: incident.lead&.platform_user_id,
          channel_id: channel_id,
          relationship_text: Formatting.relationship_summary(incident),
          custom_fields_text: Formatting.custom_fields_summary(incident)
        )
      end
    end
  end
end
