module Slack
  module Messages
    # A line about a temporary change Halon made, such as the reminder before Firefight undoes it. While it is still in
    # place it offers Keep it, One more hour and Undo now. In the asker's direct messages it also offers to open the chat when
    # the chat is on the dashboard.
    module MitigationNotice
      TITLES = {
        Conversation::Mitigations::KIND_REMINDER => ":alarm_clock:", Conversation::Mitigations::KIND_KEPT => ":pushpin:",
        Conversation::Mitigations::KIND_EXTENDED => ":hourglass_flowing_sand:", Conversation::Mitigations::KIND_ENDED => ":leftwards_arrow_with_hook:"
      }.freeze

      def self.build(notice, direct: false)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{TITLES.fetch(notice.kind, ':leftwards_arrow_with_hook:')}  *#{Mrkdwn.escape(title(notice))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(notice.text).truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        buttons = (notice.live ? live_buttons(notice) : []) + [ (WatchUpdate.link(notice.conversation_id) if direct) ].compact
        blocks << { type: "actions", elements: buttons } if buttons.any?
        blocks
      end

      def self.title(notice) = "Temporary change: #{notice.title}".truncate(150)

      def self.fallback(notice) = "#{title(notice)}. #{notice.text}"

      def self.live_buttons(notice)
        value = notice.id.to_s
        [
          { type: "button", text: { type: "plain_text", text: "Keep it" }, action_id: Identifiers::MITIGATION_KEEP, value: value },
          { type: "button", text: { type: "plain_text", text: "One more hour" }, action_id: Identifiers::MITIGATION_EXTEND, value: value },
          {
            type: "button", style: "danger", text: { type: "plain_text", text: "Undo now" }, action_id: Identifiers::MITIGATION_UNDO, value: value,
            confirm: {
              title: { type: "plain_text", text: "Undo it now?" },
              text: { type: "plain_text", text: "Firefight puts back what this changed, as the person who asked for it, and says how it went here.".truncate(300) },
              confirm: { type: "plain_text", text: "Undo now" }, deny: { type: "plain_text", text: "Cancel" }
            }
          }
        ]
      end
    end
  end
end
