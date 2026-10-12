module Slack
  module Messages
    # A message posted as Firefight in a channel someone named, such as release notes in #general, with who asked for it
    # in the footer. Halon or an outside agent wrote the words, so they are escaped before the markdown is drawn, and a
    # post can never ping the channel or the workspace.
    module ChannelPost
      HALON_TITLE = "Message from Halon".freeze
      FIREFIGHT_TITLE = "Message from Firefight".freeze
      FALLBACK_LIMIT = 150

      def self.build(message, posted_by:, by_halon:)
        [
          { type: "section", text: { type: "mrkdwn", text: ":mega:  *#{title(by_halon)}*" } },
          { type: "divider" },
          *Formatting.quoted_blocks(Mrkdwn.escape(message)),
          { type: "context", elements: [ { type: "mrkdwn", text: footer(posted_by, by_halon) } ] }
        ]
      end

      def self.fallback(message, by_halon:)
        first_line = message.to_s.strip.lines.first.to_s.strip
        "#{title(by_halon)}: #{Mrkdwn.escape(first_line).truncate(FALLBACK_LIMIT)}"
      end

      def self.title(by_halon) = by_halon ? HALON_TITLE : FIREFIGHT_TITLE

      def self.footer(posted_by, by_halon)
        return "Posted by Halon at the request of #{Mrkdwn.mention(posted_by)}" if by_halon

        "Posted through Firefight by #{Mrkdwn.mention(posted_by)}"
      end
    end
  end
end
