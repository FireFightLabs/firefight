module Slack
  module Messages
    module Shoutout
      def self.build(incident, from:, to:, message:)
        [
          { type: "section", text: { type: "mrkdwn", text: ":heart_on_fire:  *Shoutout*" } },
          { type: "divider" },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "#{Mrkdwn.mention(from)} gave a shoutout to #{Mrkdwn.mention(to)}\n> #{message}"
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
            text: { type: "mrkdwn", text: ":heart_on_fire:  *Give a shoutout?*\nRecognize someone on your team for their work on this incident." }
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
