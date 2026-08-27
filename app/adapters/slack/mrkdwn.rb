module Slack
  # mrkdwn snippets, and the escaping that stops externally-supplied text
  # (alert titles from provider payloads) injecting mentions like <!channel>
  # or fake links into a block.
  module Mrkdwn
    def self.escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # A machine has no Slack account to mention, so it is named in bold rather
    # than rendered as an empty <@> that Slack shows as a broken mention.
    def self.mention(actor)
      return "someone" unless actor
      return "<@#{actor.platform_user_id}>" if actor.platform_user_id.present?

      "*#{escape(actor.actor_display_name)}*"
    end
  end
end
