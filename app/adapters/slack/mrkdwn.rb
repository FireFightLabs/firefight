module Slack
  # Escapes Slack's control characters so externally-supplied text (alert
  # titles from provider payloads) can't inject mentions like <!channel> or
  # fake links into mrkdwn blocks.
  module Mrkdwn
    def self.escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end
