module Slack
  # Escaping stops external text such as alert titles injecting <!channel>
  # or fake links into a block.
  module Mrkdwn
    def self.escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # A machine has no Slack account, so it is named in bold instead of a
    # broken <@> mention.
    def self.mention(actor)
      return "someone" unless actor
      return "<@#{actor.platform_user_id}>" if actor.platform_user_id.present?

      "*#{escape(actor.actor_display_name)}*"
    end
  end
end
