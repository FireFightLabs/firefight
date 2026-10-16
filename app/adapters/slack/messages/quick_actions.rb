module Slack
  module Messages
    module QuickActions
      # The pinned message in the incident's channel: the title, the state and who declared it on one line, the summary,
      # then the buttons. The announcement says the same in its own card, so neither lists the fields one by one.
      def self.build(incident)
        state = [ IncidentDetail.state_line_for(incident), IncidentDetail.declared_by_line(incident) ]
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::DECLARED}  *#{Mrkdwn.escape(IncidentDetail.title_for(incident))}*" } },
          Slack::Blocks.context(state.join(IncidentDetail::SEPARATOR))
        ]
        blocks << Slack::Blocks.context(IncidentDetail::TEST_NOTE) if incident.is_test?
        blocks.concat(Formatting.quoted_blocks(incident.summary))
        blocks.concat(IncidentDetail.extra_blocks(incident))

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
