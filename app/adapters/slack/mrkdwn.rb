module Slack
  # Escaping stops external text such as alert titles injecting <!channel>
  # or fake links into a block.
  module Mrkdwn
    def self.escape(text)
      text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    # A machine, or a person who joined by email and has no Slack account, is
    # named in bold instead of a broken <@> mention.
    def self.mention(actor)
      return "someone" unless actor

      person(actor.platform_user_id, actor.actor_display_name)
    end

    # The same rule for callers holding the id and the name rather than the
    # actor, such as a workflow reading both from its context. bold also
    # bolds a real mention, for lines that always show the person in bold.
    def self.person(platform_user_id, name, bold: false)
      if platform_user_id.present?
        mention = "<@#{platform_user_id}>"
        return bold ? "*#{mention}*" : mention
      end
      return "*#{escape(name)}*" if name.present?

      "someone"
    end
  end
end
