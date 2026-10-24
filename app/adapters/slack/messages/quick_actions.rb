module Slack
  module Messages
    module QuickActions
      # The pinned message in the incident's channel: the same details as the announcement, then the quick actions.
      def self.build(incident)
        # No channel row, this message is pinned inside that channel.
        blocks = IncidentDetail.for_incident(incident)

        # Slack rejects an empty actions block, so a terminal incident drops
        # the block and its divider.
        actions = buttons(incident)
        if actions.any?
          blocks << { type: "divider" }
          blocks << { type: "actions", elements: actions }
        end

        blocks
      end

      def self.buttons(incident)
        return [] unless incident.incident_status.incident_lifecycle_stage.open?

        result = []

        if incident.incident_status.triage?
          result << {
            type: "button",
            text: { type: "plain_text", text: "#{Slack::Emoji::ACCEPTED} Accept incident", emoji: true },
            action_id: Identifiers::ACCEPT_INCIDENT,
            value: incident.id,
            style: "primary"
          }
          # Without this the only exit from triage is to accept, then cancel.
          result << {
            type: "button",
            text: { type: "plain_text", text: "#{Slack::Emoji::CANCELED} Cancel incident", emoji: true },
            action_id: Identifiers::CANCEL_INCIDENT,
            value: incident.id
          }
        end

        unless incident.lead
          result << {
            type: "button",
            text: { type: "plain_text", text: "#{Slack::Emoji::LEAD} Make me Lead", emoji: true },
            action_id: Identifiers::SET_INCIDENT_LEAD_SELF,
            value: incident.id
          }
        end

        result << {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::SUMMARY} Update summary", emoji: true },
          action_id: Identifiers::UPDATE_INCIDENT_SUMMARY,
          value: incident.id
        }

        if Investigation.available_for?(incident.workspace)
          result << {
            type: "button",
            text: { type: "plain_text", text: ":mag: Investigate", emoji: true },
            action_id: Identifiers::START_INVESTIGATION,
            value: incident.id
          }
        end

        result << {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::ESCALATED} Escalate", emoji: true },
          action_id: Identifiers::ESCALATE_INCIDENT,
          value: incident.id
        }

        result << {
          type: "button",
          text: { type: "plain_text", text: "#{Slack::Emoji::RESOLVED} Resolve", emoji: true },
          action_id: Identifiers::RESOLVE_INCIDENT,
          value: incident.id
        }

        result
      end
    end
  end
end
