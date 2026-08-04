module Slack
  module Messages
    module Escalation
      # Identical body used for the in-channel post and the announcement thread.
      def self.build(_incident, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
        blocks = [
          { type: "header", text: { type: "plain_text", text: ":rotating_light: Incident Escalated", emoji: true } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: ":firefighter: *Escalated to:* <@#{escalated_to_platform_user_id}>" } },
          { type: "section", text: { type: "mrkdwn", text: ":mega: *Escalated by:* <@#{escalated_by_platform_user_id}>" } }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: "> #{reason}" } } if reason.present?
        blocks
      end

      # DM sent to the person being escalated to. `variant: :initial` is the
      # first ping; `variant: :nudge` is the reminder sent if they haven't
      # acknowledged.
      def self.direct_message(incident, escalated_by_platform_user_id:, escalation_event_id:, reason: nil, variant: :initial)
        config = case variant
        when :initial then { header_emoji: ":rotating_light:", header_suffix: "Escalation", body: "*You've been pulled into this incident*" }
        when :nudge   then { header_emoji: ":bell:",            header_suffix: "Escalation Reminder", body: "*This incident is still waiting for your response*" }
        end

        blocks = [
          { type: "header", text: { type: "plain_text", text: "#{config[:header_emoji]} #{incident.identifier} · #{config[:header_suffix]}", emoji: true } },
          { type: "section", text: { type: "mrkdwn", text: config[:body] } },
          { type: "section", text: { type: "mrkdwn", text: ":mega: *Escalated by:* <@#{escalated_by_platform_user_id}>" } },
          { type: "section", text: { type: "mrkdwn", text: ":speech_balloon: *Channel:* <##{incident.channel_id}>" } }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: "> #{reason}" } } if reason.present?
        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: ":white_check_mark: Acknowledge", emoji: true },
              action_id: Identifiers::ACKNOWLEDGE_ESCALATION,
              value: { incident_id: incident.id, escalation_event_id: escalation_event_id }.to_json
            }
          ]
        }
        blocks
      end

      # Rewrites the original escalation DM after acknowledgment: drops the
      # action buttons and appends a confirmation section.
      def self.dm_after_acknowledgment(original_blocks)
        stripped = (original_blocks || []).reject { |b| b["type"] == "actions" || b[:type] == "actions" }
        stripped + [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":white_check_mark:  *You acknowledged this escalation*" }
          }
        ]
      end

      def self.acknowledged(_incident, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
        [
          { type: "section", text: { type: "mrkdwn", text: ":white_check_mark:  *Escalation acknowledged*" } },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: ":firefighter: <@#{escalated_to_platform_user_id}> joined the incident" } ]
          }
        ]
      end
    end
  end
end
