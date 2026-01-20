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

    # Ephemeral preview message (only visible to clicking user)
    def self.preview_announcement_blocks(user_id)
      {
        blocks: [
          {
            type: "context",
            elements: [
              {
                type: "mrkdwn",
                text: "_Only visible to you_"
              }
            ]
          },
          {
            type: "header",
            text: {
              type: "plain_text",
              text: "[PREVIEW] Website is down",
              emoji: true
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "The marketing website is down: I'm getting a '502 Gateway OverallTimeout' error"
            }
          },
          {
            type: "divider"
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "🔥 *Severity:* Minor"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "📊 *Status:* Investigating"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "👤 *Reporter:* <@#{user_id}>"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: ":firefighter: *Incident Lead:* <@#{user_id}>"
            }
          },
          {
            type: "divider"
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "🌐 Incident homepage",
                  emoji: true
                },
                action_id: "preview_homepage_disabled",
                style: "primary"
              },
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "📌 Subscribe",
                  emoji: true
                },
                action_id: "preview_subscribe_disabled"
              }
            ]
          }
        ]
      }
    end
  end
end
