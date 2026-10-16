module Slack
  module Messages
    # A notice an admin is sent directly (PlatformAdapter::Notice): a warning title, a divider, what it means, and a
    # button to the page that fixes it when there is one.
    module Notice
      def self.build(notice)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{Slack::Emoji::WARNING}  *#{Mrkdwn.escape(notice.title)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(notice.body) } }
        ]
        return blocks if notice.link_url.blank?

        blocks << { type: "actions", elements: [
          { type: "button", text: { type: "plain_text", text: notice.link_label }, url: notice.link_url, style: "primary" }
        ] }
      end
    end
  end
end
