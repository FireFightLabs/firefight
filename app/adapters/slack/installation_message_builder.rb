module Slack
  class InstallationMessageBuilder
    def self.preview_announcement_blocks(user_id)
      preview_blocks = [
        {
          type: "context",
          elements: [ { type: "mrkdwn", text: "_Only visible to you_" } ]
        }
      ]

      preview_blocks += Slack::Messages::Announcement.build_from(
        title: "[PREVIEW] Website is down",
        summary: "The marketing website is down: I'm getting a '502 Gateway OverallTimeout' error",
        severity_name: "Minor",
        status_name: "Investigating",
        reporter_id: user_id
      )

      { blocks: preview_blocks }
    end

    def self.introduction(user_id, channel_id)
      "👋 #{Slack::Mrkdwn.person(user_id, nil)} is using Firefight in your Slack workspace\n\nFirefight helps your team manage incidents with better " \
        "coordination and full visibility into what's happening.\n\nJoin the <##{channel_id}> channel to stay informed about active " \
        "incidents, or explore the commands to see how Firefight can help during outages."
    end

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
              text: introduction(user_id, channel_id)
            }
          },
          {
            type: "input",
            block_id: Identifiers::SHARE_TARGET_BLOCK,
            element: {
              type: "multi_conversations_select",
              action_id: Identifiers::SHARE_TARGET_SELECT,
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

    def self.share_message(sharing_user_id, channel_id, team_id)
      {
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: introduction(sharing_user_id, channel_id)
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
