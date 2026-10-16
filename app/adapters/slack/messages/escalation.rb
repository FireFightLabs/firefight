module Slack
  module Messages
    module Escalation
      # An alert naming who was pulled in and by whom, then the reason when one was given.
      def self.build(_incident, escalated_by:, escalated_to:, rich:, reason: nil)
        alert = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::LEVEL_WARNING, text: headline(escalated_by, escalated_to), emoji: Slack::Emoji::ESCALATED)
        body = Formatting.quoted_blocks(reason)
        [ *alert.to_blocks(rich: rich), *([ { type: "divider" } ] if body.any?), *body ]
      end

      def self.headline(escalated_by, escalated_to)
        "Escalated to #{Mrkdwn.mention(escalated_to)} by #{Mrkdwn.mention(escalated_by)}"
      end

      # `variant: :nudge` is the reminder sent when they have not acknowledged.
      def self.direct_message(incident, escalated_by:, escalation_event_id:, reason: nil, variant: :initial)
        config = case variant
        when :initial then { header_emoji: Slack::Emoji::ESCALATED, header_suffix: "Escalated to you", body: "*You've been pulled into this incident*" }
        when :nudge   then { header_emoji: Slack::Emoji::REMINDER, header_suffix: "Escalation reminder", body: "*This incident is still waiting for your response*" }
        end

        blocks = [
          { type: "header", text: { type: "plain_text", text: "#{config[:header_emoji]} #{incident.identifier} · #{config[:header_suffix]}", emoji: true } },
          { type: "section", text: { type: "mrkdwn", text: config[:body] } },
          *Formatting.quoted_blocks(reason),
          { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::ESCALATED} *Escalated by:* #{Mrkdwn.mention(escalated_by)}" } },
          { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::CHANNEL} *Channel:* <##{incident.channel_id}>" } }
        ]
        blocks << {
          type: "actions",
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "#{Slack::Emoji::ACKNOWLEDGED} Acknowledge", emoji: true },
              action_id: Identifiers::ACKNOWLEDGE_ESCALATION,
              value: { incident_id: incident.id, escalation_event_id: escalation_event_id }.to_json
            }
          ]
        }
        blocks
      end

      def self.dm_after_acknowledgment(original_blocks)
        stripped = (original_blocks || []).reject { |b| b["type"] == "actions" || b[:type] == "actions" }
        stripped + [
          {
            type: "section",
            text: { type: "mrkdwn", text: "#{Slack::Emoji::ACKNOWLEDGED}  *You acknowledged this escalation*" }
          }
        ]
      end

      def self.acknowledged(_incident, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
        [
          { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::ACKNOWLEDGED}  *Escalation acknowledged*" } },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: "#{Slack::Emoji::LEAD} #{Mrkdwn.person(escalated_to_platform_user_id, nil)} joined the incident" } ]
          }
        ]
      end
    end
  end
end
