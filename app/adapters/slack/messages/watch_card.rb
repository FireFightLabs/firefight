module Slack
  module Messages
    # A watch Halon keeps, as one card per place it reports, edited in place as it moves: what it is for, how it stands in
    # a word and one plain line on why. While it goes it offers Stop, which asks first as the dashboard's Stop does. It
    # opens the run's page when the provider gave one, and in the asker's direct messages the chat when the chat is on the
    # dashboard. Its end is also said in a short line of its own (ended), since editing the card notifies nobody.
    module WatchCard
      ICONS = {
        Chat::Watch::STATUS_ACTIVE => ":eyes:", Chat::Watch::STATUS_SUCCEEDED => ":white_check_mark:", Chat::Watch::STATUS_FAILED => ":x:",
        Chat::Watch::STATUS_TIMED_OUT => ":hourglass:", Chat::Watch::STATUS_STOPPED => ":octagonal_sign:"
      }.freeze
      LEVELS = {
        Chat::Watch::STATUS_SUCCEEDED => Blocks::Alert::LEVEL_SUCCESS, Chat::Watch::STATUS_FAILED => Blocks::Alert::LEVEL_ERROR,
        Chat::Watch::STATUS_TIMED_OUT => Blocks::Alert::LEVEL_WARNING, Chat::Watch::STATUS_STOPPED => Blocks::Alert::LEVEL_DEFAULT
      }.freeze
      STOP = "Stop".freeze
      OPEN_RUN = "Open the run".freeze
      OPEN_CHAT = "Open the chat".freeze

      # card is a Conversation::Watches::Card. rich is whether the workspace's Slack shows card blocks.
      def self.build(card, rich:)
        Blocks::Card.new(icon: icon(card), title: Mrkdwn.escape(card.what), subtitle: card.state, body: Mrkdwn.escape(card.why),
                         actions: [ (stop_button(card) if card.live?), run_link(card), link(card.conversation_id) ].compact).to_blocks(rich: rich)
      end

      # How it ended, as one line led by its mark, such as "Done: Ship main. Took 7 minutes."
      def self.ended(card)
        text = "*#{card.state}: #{Mrkdwn.escape(card.what)}.* #{Mrkdwn.escape(card.why)}".strip
        Blocks::Alert.new(level: LEVELS.fetch(card.status, Blocks::Alert::LEVEL_DEFAULT), text: text, emoji: icon(card)).to_blocks(rich: false)
      end

      def self.fallback(card) = "#{card.state}: #{card.what}. #{card.why}".strip

      def self.icon(card) = ICONS.fetch(card.status, ":eyes:")

      def self.run_link(card)
        return if card.link.blank?

        { type: "button", text: { type: "plain_text", text: OPEN_RUN }, url: card.link }
      end

      def self.link(conversation_id)
        url = conversation_id && DashboardUrl.agent_chat(conversation_id)
        return unless url

        { type: "button", text: { type: "plain_text", text: OPEN_CHAT }, url: url }
      end

      def self.stop_button(card)
        {
          type: "button", text: { type: "plain_text", text: STOP }, action_id: Identifiers::WATCH_STOP, value: card.update_id.to_s,
          confirm: {
            title: { type: "plain_text", text: "Stop watching?" },
            text: { type: "plain_text", text: "Halon stops watching this and says so here. It will not report on it again." },
            confirm: { type: "plain_text", text: "Stop watching" }, deny: { type: "plain_text", text: "Cancel" }
          }
        }
      end
    end
  end
end
