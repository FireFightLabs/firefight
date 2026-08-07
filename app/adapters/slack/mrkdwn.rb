module Slack
  # mrkdwn snippets, and the escaping that stops externally-supplied text
  # (alert titles from provider payloads) injecting mentions like <!channel>
  # or fake links into a block.
  module Mrkdwn
    def self.escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def self.mention(membership)
      membership ? "<@#{membership.platform_user_id}>" : "someone"
    end
  end
end
