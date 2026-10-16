module Slack
  module Messages
    # Posted once and updated in place as the alert re-fires or resolves.
    module Alert
      def self.build(alert)
        emoji = alert.firing? ? Slack::Emoji::ALERT_FIRING : Slack::Emoji::ALERT_RESOLVED
        title = Slack::Mrkdwn.escape(alert.title)
        title = "<#{alert.source_url.delete('<>|')}|#{title}>" if alert.source_url

        [
          { type: "section", text: { type: "mrkdwn", text: "#{emoji}  *#{title}*" } },
          {
            type: "context",
            elements: [
              { type: "mrkdwn", text: [ alert.alert_source.name, alert.status, "fired #{alert.event_count}x", "last #{alert.last_seen_at.utc.strftime('%H:%M UTC')}" ].join(Formatting::SEPARATOR) }
            ]
          }
        ]
      end
    end
  end
end
