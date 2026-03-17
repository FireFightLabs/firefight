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
                action_id: Identifiers::SHARE_INCIDENTS_CHANNEL,
                style: "primary"
              },
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: "📢 Preview an announcement",
                  emoji: true
                },
                action_id: Identifiers::PREVIEW_ANNOUNCEMENT
              }
            ]
          }
        ]
      }
    end

    # Ephemeral preview message (only visible to clicking user)
    def self.preview_announcement_blocks(user_id)
      preview_blocks = [
        {
          type: "context",
          elements: [ { type: "mrkdwn", text: "_Only visible to you_" } ]
        }
      ]

      preview_blocks += Slack::IncidentMessageBuilder.announcement_blocks_for({
        title: "[PREVIEW] Website is down",
        summary: "The marketing website is down: I'm getting a '502 Gateway OverallTimeout' error",
        severity_name: "Minor",
        status_name: "Investigating",
        reporter_id: user_id
      })

      { blocks: preview_blocks }
    end

    # Share channel modal
    def self.share_channel_modal(user_id, channel_id)
      {
        type: "modal",
        callback_id: Identifiers::SHARE_INCIDENTS_CHANNEL_MODAL,
        title: {
          type: "plain_text",
          text: "Share this channel"
        },
        submit: {
          type: "plain_text",
          text: "Share"
        },
        close: {
          type: "plain_text",
          text: "Cancel"
        },
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "👋 <@#{user_id}> is using FireFight in your Slack workspace\n\nFireFight helps your team manage incidents with better coordination and full visibility into what's happening.\n\nJoin the <##{channel_id}> channel to stay informed about active incidents, or explore the commands to see how FireFight can help during outages."
            }
          },
          {
            type: "input",
            block_id: "share_target_block",
            element: {
              type: "multi_conversations_select",
              action_id: "share_target_select",
              placeholder: {
                type: "plain_text",
                text: "Select channels or people"
              }
            },
            label: {
              type: "plain_text",
              text: "Where should we share this?"
            }
          }
        ]
      }
    end

    # Message sent when sharing the channel
    def self.share_message(sharing_user_id, channel_id, team_id)
      {
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "👋 <@#{sharing_user_id}> is using FireFight in your Slack workspace\n\nFireFight helps your team manage incidents with better coordination and full visibility into what's happening.\n\nJoin the <##{channel_id}> channel to stay informed about active incidents, or explore the commands to see how FireFight can help during outages."
            }
          },
          {
            type: "actions",
            elements: [
              {
                type: "button",
                text: {
                  type: "plain_text",
                  text: ":slack: Join the channel",
                  emoji: true
                },
                url: "slack://channel?team=#{team_id}&id=#{channel_id}",
                style: "primary"
              }
            ]
          }
        ]
      }
    end
  end
end
