module Slack
  module Messages
    # Quick-actions message posted and pinned in the incident channel.
    # Acts as the channel header: severity, status, lead, custom fields,
    # plus the action buttons (accept, lead, summary, escalate).
    module QuickActions
      def self.build(incident)
        # No channel line: this message is pinned inside the channel it would
        # point at.
        blocks = IncidentDetail.for_incident(incident)

        # Slack rejects an actions block with no elements, so a terminal
        # incident drops the block and its divider rather than emptying it.
        actions = buttons(incident)
        if actions.any?
          blocks << { type: "divider" }
          blocks << { type: "actions", elements: actions }
        end

        blocks
      end

      def self.buttons(incident)
        # A resolved or canceled incident is over. Offering Escalate or Make me
        # Lead on it invites actions that no longer mean anything.
        return [] unless incident.incident_status.incident_lifecycle_stage.open?

        result = []

        if incident.incident_status.triage?
          result << {
            type: "button",
            text: { type: "plain_text", text: ":white_check_mark: Accept incident", emoji: true },
            action_id: Identifiers::ACCEPT_INCIDENT,
            value: incident.id,
            style: "primary"
          }
          # The only other way out of triage. Without it the sole exit is to
          # accept something you do not believe in, then cancel it.
          result << {
            type: "button",
            text: { type: "plain_text", text: ":wastebasket: Cancel incident", emoji: true },
            action_id: Identifiers::CANCEL_INCIDENT,
            value: incident.id
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
