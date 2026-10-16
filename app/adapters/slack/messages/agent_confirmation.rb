module Slack
  module Messages
    # The calls the agent paused on in a thread. Each is a card asking in plain words what Halon wants to do, one line on
    # what it changes or why, and Approve, Cancel and Details, with everything else under Details
    # (Modals::AgentConfirmationDetails). Once answered, the same message is redrawn to how it stands: a checklist while
    # an approved change runs (ChangeProgress), then one line saying it is done, failed or cancelled.
    module AgentConfirmation
      EMOJI = {
        awaiting: ":raised_hand:", owner_asked: ":hourglass:", done: ":white_check_mark:", failed: ":x:", stopped: ":heavy_minus_sign:",
        cancelled: ":no_entry_sign:", withdrawn: ":heavy_minus_sign:"
      }.freeze
      WITHDRAWN = "Withdrawn. Something else was asked first, so this was not run.".freeze
      STOPPED = "Stopped before it finished.".freeze
      DID_NOT_GO_THROUGH = "It did not go through.".freeze
      ALLOW_FOR_CHAT = "Allow for this chat".freeze
      DETAILS = "Details".freeze
      CANCEL = "Cancel".freeze
      # Slack takes 50 blocks in a message.
      MAX_BLOCKS = 50
      REASON_LIMIT = 200
      LINK_TEXT_LIMIT = 60

      # rich is whether the workspace's Slack shows card and plan blocks. Plain, questions are kept apart by a divider,
      # which many at once drop, then put each question's buttons in one row, then drop their lines, so every one keeps its
      # buttons under Slack's limit.
      def self.build(conversation_id:, confirmations:, rich: false)
        questions = confirmations.map { |confirmation| question_blocks(conversation_id, confirmation, rich: rich) }
        divided = rich ? questions.flatten : questions.each_with_index.flat_map { |blocks, index| index.positive? ? [ { type: "divider" }, *blocks ] : blocks }
        return divided if divided.size <= MAX_BLOCKS

        joined = questions.flat_map { |blocks| join_actions(blocks) }
        joined.size <= MAX_BLOCKS ? joined : joined.reject { |block| block[:type] == "context" }
      end

      # A question's buttons in one row, where the plain form put Allow for this chat in a row of its own.
      def self.join_actions(blocks)
        blocks.each_with_object([]) do |block, joined|
          next joined << block unless block[:type] == "actions" && joined.last&.dig(:type) == "actions"

          joined[-1] = joined.last.merge(elements: joined.last[:elements] + block[:elements])
        end
      end

      def self.fallback(confirmations)
        return confirmations.map { |confirmation| plain_state(confirmation) }.join(" ") if confirmations.none? { |confirmation| confirmation.status == :awaiting }

        "#{Chat::Tools::WANTS_TO} #{confirmations.map(&:action).join(', ')}"
      end

      def self.question_blocks(conversation_id, confirmation, rich:)
        value = "#{conversation_id}:#{confirmation.tool_call_id}"
        case state(confirmation)
        when :awaiting then request_blocks(value, confirmation, rich: rich)
        when :working
          footer = [ "Approved by #{Mrkdwn.mention(confirmation.decided_by)}", (started(confirmation.progress) if confirmation.progress) ].compact.join("  ·  ")
          ChangeProgress.blocks(title: confirmation.action.upcase_first, work: confirmation.progress, footer: footer, details: details_button(value), rich: rich)
        else
          Blocks::Card.new(icon: EMOJI.fetch(state(confirmation)), title: Mrkdwn.escape(confirmation.action.upcase_first), body: state_words(confirmation),
                           actions: [ details_button(value) ]).to_blocks(rich: rich)
        end
      end

      # The card, then what a card cannot hold: allowing it for the rest of the chat where it may be
      # (Confirmation#allowable?), and when a change customers feel is undone, kept as soon as it is picked.
      def self.request_blocks(value, confirmation, rich:)
        actions = [
          { type: "button", style: "primary", action_id: Identifiers::AGENT_CONFIRM, text: { type: "plain_text", text: Chat::Tools::APPROVE }, value: value },
          { type: "button", action_id: Identifiers::AGENT_CANCEL, text: { type: "plain_text", text: CANCEL }, value: value },
          details_button(value)
        ]
        card = Blocks::Card.new(icon: EMOJI[:awaiting], title: Mrkdwn.escape(confirmation.heading), body: line_text(confirmation), actions: actions)
        allow = ({ type: "actions", elements: [ { type: "button", action_id: Identifiers::AGENT_ALLOW_FOR_CHAT, text: { type: "plain_text", text: ALLOW_FOR_CHAT }, value: value } ] } if confirmation.allowable?)
        [ *card.to_blocks(rich: rich), (expiry_block(value, confirmation) if confirmation.expires.any?), allow ].compact
      end

      # The one line, with the caution folded in when outside text holding the change's own values was read. A card's
      # body holds 200 characters, so the line gives way to the caution.
      def self.line_text(confirmation)
        caution = (":warning: _#{Mrkdwn.escape(confirmation.caution)}_" if confirmation.caution)
        room = Blocks::Card::BODY_LIMIT - (caution ? caution.length + 2 : 0)
        line = (Mrkdwn.escape(confirmation.line).truncate([ room, 40 ].max) if confirmation.line)
        [ line, caution ].compact.join("  ").presence
      end

      def self.details_button(value)
        { type: "button", action_id: Identifiers::AGENT_CONFIRMATION_DETAILS, text: { type: "plain_text", text: DETAILS }, value: value }
      end

      def self.expiry_block(value, confirmation)
        options = confirmation.expires.map { |expiry| { text: { type: "plain_text", text: expiry.label }, value: "#{value}:#{expiry.value}" } }
        chosen = options.find { |option| option[:value] == "#{value}:#{confirmation.chosen_expiry}" } || options.first
        { type: "section", text: { type: "mrkdwn", text: confirmation.undo_label },
          accessory: { type: "static_select", action_id: Identifiers::AGENT_EXPIRY, initial_option: chosen, options: options } }
      end

      def self.started(work) = "started #{Formatting.slack_time(work.started_at)}"

      def self.state(confirmation)
        return confirmation.status unless confirmation.status == :confirmed

        outcome = confirmation.outcome
        return :working unless outcome
        return :done if outcome.kind == Chat::StepOutcome::KIND_ANSWERED
        return :stopped if outcome.kind == Chat::StepOutcome::KIND_STOPPED

        :failed
      end

      def self.state_words(confirmation)
        by = Mrkdwn.mention(confirmation.decided_by)
        case state(confirmation)
        when :owner_asked then "Approved by #{by}  ·  waiting for #{Mrkdwn.escape(confirmation.waiting_on)} to agree"
        when :done then [ "Done", link(confirmation.outcome&.link || pull_request(confirmation)), "approved by #{by}" ].compact.join("  ·  ")
        when :failed then "Failed: #{Mrkdwn.escape(failure(confirmation))}"
        when :stopped then STOPPED
        when :cancelled then "Cancelled by #{by}"
        else WITHDRAWN
        end
      end

      def self.pull_request(confirmation)
        url = confirmation.progress&.pull_request
        Chat::StepOutcome::Link.new(provider: nil, url: url) if url.present?
      end

      # The page the result came from, with its address as the words, so where it went is visible before it is opened.
      def self.link(cited)
        return unless cited&.url.present?

        shown = cited.url.sub(%r{\Ahttps?://}, "").delete_suffix("/").truncate(LINK_TEXT_LIMIT)
        "<#{cited.url}|#{Mrkdwn.escape(shown)}>"
      end

      def self.failure(confirmation)
        said = confirmation.progress&.reason.presence || confirmation.outcome&.said
        said.present? ? Chat::Tools.plain(said, REASON_LIMIT) : DID_NOT_GO_THROUGH
      end

      # The same state in words for the notification text, which has no formatting.
      def self.plain_state(confirmation)
        words = { working: "approved, working on it", owner_asked: "approved", done: "done", failed: "failed", stopped: "stopped",
                  cancelled: "cancelled" }.fetch(state(confirmation), "withdrawn")
        "#{confirmation.action.upcase_first}: #{words}."
      end
    end
  end
end
