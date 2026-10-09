module Slack
  module Messages
    # One line a watch Halon keeps said, titled by what is watched. In the asker's direct messages it also offers to open
    # the chat when the chat is on the dashboard.
    module WatchUpdate
      TITLES = {
        Chat::Watch::Update::KIND_STARTED => ":eyes:", Chat::Watch::Update::KIND_MILESTONE => ":large_green_circle:",
        Chat::Watch::Update::KIND_PART_FAILED => ":x:", Chat::Watch::Update::KIND_HANDED_BACK => ":warning:",
        Chat::Watch::Update::KIND_SLOW => ":hourglass_flowing_sand:", Chat::Watch::Update::KIND_PROGRESS => ":large_blue_circle:", Conversation::Watches::TONE_DONE => ":white_check_mark:",
        Conversation::Watches::TONE_FAILED => ":x:", Conversation::Watches::TONE_TIMED_OUT => ":hourglass:",
        Conversation::Watches::TONE_STOPPED => ":octagonal_sign:"
      }.freeze

      def self.build(update, direct: false, conversation_id: nil)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{TITLES.fetch(update.tone, ':eyes:')}  *#{Mrkdwn.escape(title(update))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(update.text).truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        open = direct && link(conversation_id)
        blocks << open if open
        blocks
      end

      def self.title(update) = "Watching #{update.title}"

      def self.fallback(update) = "#{title(update)}: #{update.text}"

      def self.link(conversation_id)
        url = conversation_id && DashboardUrl.agent_chat(conversation_id)
        return unless url

        { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open the chat" }, url: url } ] }
      end
    end
  end
end
