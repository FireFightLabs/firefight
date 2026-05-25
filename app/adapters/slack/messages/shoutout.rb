module Slack
  module Messages
    module Shoutout
      def self.build(incident, from_user_id:, recipient_user_id:, message:)
        [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: ":heart_on_fire: *Shoutout*\n<@#{from_user_id}> gave a shoutout to <@#{recipient_user_id}>\n> #{message}"
            }
          },
          {
            type: "context",
            elements: [ { type: "mrkdwn", text: "During <##{incident.channel_id}> · #{incident.identifier}" } ]
          }
        ]
      end

      def self.from_reaction(incident_id)
        [
          {
            type: "section",
            text: { type: "mrkdwn", text: ":heart_on_fire: *Give a shoutout?*\nRecognize someone on your team for their work on this incident." }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: { type: "plain_text", text: "Give a shoutout", emoji: true },
                action_id: Identifiers::SHOUTOUT_FROM_REACTION,
                value: { incident_id: incident_id }.to_json,
                style: "primary"
              }
            ]
          }
        ]
      end
    end
  end
end
