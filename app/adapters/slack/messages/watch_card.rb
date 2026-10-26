module Slack
  module Messages
    # A watch Halon keeps, as one message per place it reports, edited in place as it moves: a live checklist of what it
    # follows (Checklist), named for what the watch is for, each step with how it stands and its line. Under it the
    # watch's state in a word led by its mark, with why it ended once it has, then the buttons. While it goes it offers
    # Stop, which asks first as the dashboard's Stop does. It opens the run's page when the provider gave one, and in the
    # asker's direct messages the chat when the chat is on the dashboard. Its end is also said in a short line of its own
    # (ended), since editing the message notifies nobody.
    module WatchCard
      ICONS = {
        Chat::Watch::STATUS_ACTIVE => ":eyes:", Chat::Watch::STATUS_SUCCEEDED => ":white_check_mark:", Chat::Watch::STATUS_FAILED => ":x:",
        Chat::Watch::STATUS_TIMED_OUT => ":hourglass:", Chat::Watch::STATUS_STOPPED => ":octagonal_sign:"
      }.freeze
      LEVELS = {
        Chat::Watch::STATUS_SUCCEEDED => Blocks::Alert::LEVEL_SUCCESS, Chat::Watch::STATUS_FAILED => Blocks::Alert::LEVEL_ERROR,
        Chat::Watch::STATUS_TIMED_OUT => Blocks::Alert::LEVEL_WARNING, Chat::Watch::STATUS_STOPPED => Blocks::Alert::LEVEL_DEFAULT
      }.freeze
      # A step skipped or no longer followed neither ran nor failed, so it stays unticked and its line says why.
      STEP_STATUSES = {
        Chat::Watch::Step::STATUS_WAITING => Checklist::PENDING, Chat::Watch::Step::STATUS_RUNNING => Checklist::IN_PROGRESS,
        Chat::Watch::Step::STATUS_REPAIRING => Checklist::IN_PROGRESS, Chat::Watch::Step::STATUS_SUCCEEDED => Checklist::COMPLETE,
        Chat::Watch::Step::STATUS_FAILED => Checklist::ERROR, Chat::Watch::Step::STATUS_UNFOLLOWABLE => Checklist::PENDING,
        Chat::Watch::Step::STATUS_SKIPPED => Checklist::PENDING
      }.freeze
      STOP = "Stop".freeze
      OPEN_RUN = "Open the run".freeze
      OPEN_CHAT = "Open the chat".freeze

      # card is a Conversation::Watches::Card. rich is whether the workspace's Slack shows plan blocks.
      def self.build(card, rich:)
        items = card.steps.map do |step|
          Checklist::Item.new(id: step.id, title: step.label, status: STEP_STATUSES.fetch(step.status), detail: step.line)
        end
        buttons = [ (stop_button(card) if card.live?), run_link(card), link(card.conversation_id) ].compact
        [ *Checklist.blocks(title: card.what, items: items, rich: rich, emoji: icon(card)),
          { type: "context", elements: [ { type: "mrkdwn", text: standing(card, rich: rich) } ] },
          ({ type: "actions", elements: buttons } if buttons.any?) ].compact
      end

      # The state in a word, such as "Watching", and why it ended once it has. A plan's title is plain text, so the mark
      # leads this line where the plan is drawn, and leads the title where it is not.
      def self.standing(card, rich:)
        said = [ (icon(card) if rich), card.state ].compact.join("  ")
        return said if card.live? || card.why.blank?

        "#{said}  ·  #{Mrkdwn.escape(card.why)}".truncate(Formatting::SECTION_TEXT_LIMIT)
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
