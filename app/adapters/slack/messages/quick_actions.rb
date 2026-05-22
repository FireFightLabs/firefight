module Slack
  module Messages
    # Quick-actions message posted and pinned in the incident channel.
    # Acts as the channel header: severity, status, lead, custom fields,
    # plus the action buttons (accept, lead, summary, escalate).
    module QuickActions
      def self.build(incident)
        blocks = [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: ":rotating_light: #{incident.identifier} · #{incident.name || 'Untitled Incident'}",
              emoji: true
            }
          }
        ]

        if incident.summary.present?
          blocks << { type: "section", text: { type: "mrkdwn", text: "_#{incident.summary}_" } }
        end

        blocks << { type: "divider" }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":fire: *Severity:* #{incident.incident_severity.name}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":construction: *Status:* #{incident.incident_status.name}" } }
        blocks << { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Lead:* <@#{incident.lead.platform_user_id}>" } } if incident.lead
        blocks << { type: "section", text: { type: "mrkdwn", text: ":mega: *Declared by:* <@#{incident.declared_by.platform_user_id}>" } }

        custom_fields_text = Formatting.custom_fields_summary(incident)
        blocks << { type: "section", text: { type: "mrkdwn", text: custom_fields_text } } if custom_fields_text

        relationship_text = Formatting.relationship_summary(incident)
        blocks << { type: "section", text: { type: "mrkdwn", text: relationship_text } } if relationship_text

        blocks << { type: "divider" }
        blocks << { type: "actions", elements: buttons(incident) }

        blocks
      end

      def self.buttons(incident)
        result = []

        if incident.incident_status.triage?
          result << {
            type: "button",
            text: { type: "plain_text", text: ":white_check_mark: Accept incident", emoji: true },
            action_id: Identifiers::ACCEPT_INCIDENT,
            value: incident.id,
            style: "primary"
          }
        end

        unless incident.lead
          result << {
            type: "button",
            text: { type: "plain_text", text: ":firefighter: Make me Lead", emoji: true },
            action_id: Identifiers::SET_INCIDENT_LEAD_SELF,
            value: incident.id
          }
        end

        result << {
          type: "button",
          text: { type: "plain_text", text: ":memo: Update summary", emoji: true },
          action_id: Identifiers::UPDATE_INCIDENT_SUMMARY,
          value: incident.id
        }

        result << {
          type: "button",
          text: { type: "plain_text", text: ":fire_engine: Escalate", emoji: true },
          action_id: Identifiers::ESCALATE_INCIDENT,
          value: incident.id
        }

        result
      end
    end
  end
end
