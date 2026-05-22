module Slack
  module Modals
    module IncidentCreated
      def self.build(incident, team_id:)
        channel_link = "slack://channel?team=#{team_id}&id=#{incident.channel_id}"

        {
          type: "modal",
          title: { type: "plain_text", text: "Incident declared" },
          close: { type: "plain_text", text: "Close" },
          blocks: [
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: "We've created <##{incident.channel_id}> as a dedicated space to respond to this incident with your team."
              }
            },
            {
              type: "actions",
              elements: [
                {
                  type: "button",
                  text: { type: "plain_text", text: ":slack: Join incident channel", emoji: true },
                  url: channel_link
                }
              ]
            }
          ]
        }
      end
    end
  end
end
