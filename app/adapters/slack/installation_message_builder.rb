module Slack
  class InstallationMessageBuilder
    # Welcome message posted to #incidents channel
    def self.welcome_message_blocks
      {
        blocks: [
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "Welcome to FireFight!",
              emoji: true
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "*This is your central incident hub.*\n\nWhen an incident is declared, we'll spin up a dedicated response channel and post an announcement here. Each announcement stays current as the incident evolves, giving you real-time visibility across all ongoing incidents in your organization."
            }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "🔗 Share this channel",
                  emoji: true
                },
                action_id: "share_incidents_channel",
                style: "primary"
              },
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "📢 Preview an announcement",
                  emoji: true
                },
                action_id: "preview_announcement"
              }
            ]
          }
        ]
      }
    end
  end
end
