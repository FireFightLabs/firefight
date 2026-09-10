module Slack
  module Messages
    # Posted once and updated in place as the alert re-fires or resolves.
    module Alert
      def self.build(alert)
        emoji = alert.firing? ? ":rotating_light:" : ":white_check_mark:"

        [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  *#{Slack::Mrkdwn.escape(alert.title)}*" } },
          {
            type: "context",
            elements: [
              { type: "mrkdwn", text: "#{alert.alert_source.name}  |  #{alert.status}  |  fired #{alert.event_count}x  |  last #{alert.last_seen_at.utc.strftime("%H:%M UTC")}" }
            ]
          }
        ]
      end
    end
  end
end
