module Slack
  module Messages
    # One line a watch Halon keeps said, titled by what it waits on, such as Watch "Deploy finished". While the watch goes
    # it offers Stop, which asks first as the dashboard's Stop does. It opens the run's page when the provider gave one,
    # and in the asker's direct messages it also offers to open the chat when the chat is on the dashboard.
    module WatchUpdate
      TITLES = {
        Chat::Watch::Update::KIND_STARTED => ":eyes:", Chat::Watch::Update::KIND_MILESTONE => ":large_green_circle:",
        Chat::Watch::Update::KIND_PART_FAILED => ":x:", Chat::Watch::Update::KIND_HANDED_BACK => ":warning:",
        Chat::Watch::Update::KIND_REPAIRED => ":wrench:", Chat::Watch::Update::KIND_CORRECTED => ":arrows_counterclockwise:",
        Chat::Watch::Update::KIND_CEILING => ":hourglass:",
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
        buttons = [ (stop_button(update) if update.live), run_link(update), (direct && link(conversation_id)) ].compact
        blocks << { type: "actions", elements: buttons } if buttons.any?
        blocks
      end

      def self.title(update) = update.name

      def self.run_link(update)
        return if update.link.blank?

        { type: "button", text: { type: "plain_text", text: "Open the run" }, url: update.link }
      end

      def self.fallback(update) = "#{title(update)}: #{update.text}"

      def self.link(conversation_id)
        url = conversation_id && DashboardUrl.agent_chat(conversation_id)
        return unless url

        { type: "button", text: { type: "plain_text", text: "Open the chat" }, url: url }
      end

      def self.stop_button(update)
        {
          type: "button", text: { type: "plain_text", text: "Stop" }, action_id: Identifiers::WATCH_STOP, value: update.id.to_s,
          confirm: {
            title: { type: "plain_text", text: "Stop watching?" },
            text: { type: "plain_text", text: %(Halon stops watching "#{update.title}" and says so here. It will not report on it again.).truncate(300) },
            confirm: { type: "plain_text", text: "Stop watching" }, deny: { type: "plain_text", text: "Cancel" }
          }
        }
      end
    end
  end
end
