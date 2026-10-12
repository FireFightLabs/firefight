module Slack
  module Messages
    # The calls the agent paused on in a thread, each with its buttons until someone answers.
    module AgentConfirmation
      TITLE = ":raised_hand:  *Confirm before I go ahead*".freeze
      STATUS_LINES = {
        confirmed: ":white_check_mark: Confirmed", cancelled: ":no_entry_sign: Cancelled",
        withdrawn: ":heavy_minus_sign: Withdrawn. Something else was asked first, so this was not run."
      }.freeze
      ALLOW_FOR_CHAT = "Allow for this chat".freeze
      # Slack takes 50 blocks. The title and divider take two, and past that each question drops its quiet lines.
      MAX_BLOCKS = 50
      BUTTON_LIMIT = 75
      TOOL = "tool".freeze

      # A browser send is asked about under the screenshot of the page it sends from, posted just before.
      PAGE_ABOVE = "The page this sends from is in the screenshot above, as Halon's browser saw it before stopping.".freeze

      def self.build(conversation_id:, confirmations:)
        head = [ { type: "section", text: { type: "mrkdwn", text: TITLE } }, { type: "divider" } ]
        full = confirmations.flat_map { |confirmation| question_blocks(conversation_id, confirmation) }
        return head + full if head.size + full.size <= MAX_BLOCKS

        head + confirmations.flat_map { |confirmation| question_blocks(conversation_id, confirmation, compact: true) }
      end

      def self.fallback(confirmations)
        "Waiting for you to confirm: #{confirmations.map(&:title).join(', ')}"
      end

      # In the dashboard's order: what will happen, where, what it does, what it touches, why Halon proposes it, the
      # warning when outside text holds this change's own values, when it is undone, the buttons, and the call itself
      # with every read from outside last. Everything here came from the model or other systems, so it is escaped. A
      # compact question folds the sentence into the title and leaves out where it happens and the call itself.
      def self.question_blocks(conversation_id, confirmation, compact: false)
        blocks = heading_blocks(confirmation, compact: compact)
        guarded = confirmation.safeguards.map { |name, value| "*#{Slack::Mrkdwn.escape(name)}:* #{Slack::Mrkdwn.escape(value)}" }
        if guarded.any?
          blocks << { type: "section", text: { type: "mrkdwn", text: guarded.join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } }
        end
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: PAGE_ABOVE } ] } if confirmation.page
        blocks.concat(support_blocks(confirmation))
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: ":warning: #{Slack::Mrkdwn.escape(confirmation.read_lead)}" } ] } if confirmation.read_lead
        blocks.concat(answer_blocks(conversation_id, confirmation))
        blocks.concat(detail_blocks(confirmation)) unless compact
        blocks
      end

      def self.heading_blocks(confirmation, compact:)
        title = "*#{Slack::Mrkdwn.escape(confirmation.title)}*"
        summary = (Slack::Mrkdwn.escape(confirmation.summary) if confirmation.summary)
        return [ { type: "section", text: { type: "mrkdwn", text: [ title, summary ].compact.join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } } ] if compact

        blocks = [ { type: "section", text: { type: "mrkdwn", text: title.truncate(Formatting::SECTION_TEXT_LIMIT) } } ]
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: Slack::Mrkdwn.escape(confirmation.label) } ] } if confirmation.label
        blocks << { type: "section", text: { type: "mrkdwn", text: summary.truncate(Formatting::SECTION_TEXT_LIMIT) } } if summary
        blocks
      end

      # The reads from this turn Halon named as showing the change will help, as points in normal text, so the person
      # approves the reasoning too.
      def self.support_blocks(confirmation)
        return [] unless confirmation.support_lead

        points = confirmation.support_points.map do |point|
          [ "• #{Slack::Mrkdwn.escape(point.text)}", (" _(#{Slack::Mrkdwn.escape(point.source)})_" if point.source) ].join
        end
        [ { type: "section", text: { type: "mrkdwn", text: "*#{confirmation.support_lead}*\n#{points.join("\n")}".truncate(Formatting::SECTION_TEXT_LIMIT) } } ]
      end

      # When a change customers feel is undone, chosen before it is confirmed and kept as soon as it is picked, then the
      # buttons. Allow for the rest of the chat is offered only where it may be (Confirmation#allowable?). Once answered,
      # a line says how.
      def self.answer_blocks(conversation_id, confirmation)
        if confirmation.status == :owner_asked
          return [ { type: "context", elements: [ { type: "mrkdwn", text: ":hourglass: Confirmed. Waiting for #{Slack::Mrkdwn.escape(confirmation.waiting_on)} to agree." } ] } ]
        end
        status_line = STATUS_LINES[confirmation.status]
        return [ { type: "context", elements: [ { type: "mrkdwn", text: status_line } ] } ] if status_line

        value = "#{conversation_id}:#{confirmation.tool_call_id}"
        elements = [
          { type: "button", style: "primary", action_id: Identifiers::AGENT_CONFIRM,
            text: { type: "plain_text", text: confirmation.confirm_label.truncate(BUTTON_LIMIT) }, value: value },
          ({ type: "button", action_id: Identifiers::AGENT_ALLOW_FOR_CHAT,
             text: { type: "plain_text", text: ALLOW_FOR_CHAT }, value: value } if confirmation.allowable?),
          { type: "button", action_id: Identifiers::AGENT_CANCEL,
            text: { type: "plain_text", text: "Cancel" }, value: value }
        ].compact
        [ expiry_block(value, confirmation), { type: "actions", elements: elements } ].compact
      end

      def self.expiry_block(value, confirmation)
        return if confirmation.expires.empty?

        options = confirmation.expires.map { |expiry| { text: { type: "plain_text", text: expiry.label }, value: "#{value}:#{expiry.value}" } }
        chosen = options.find { |option| option[:value] == "#{value}:#{confirmation.chosen_expiry}" } || options.first
        { type: "section", text: { type: "mrkdwn", text: confirmation.undo_label },
          accessory: { type: "static_select", action_id: Identifiers::AGENT_EXPIRY, initial_option: chosen, options: options } }
      end

      # The call as the tool is given it, then every read from outside before it was asked, quiet at the foot.
      def self.detail_blocks(confirmation)
        called = [ ([ TOOL, confirmation.tool_name ] if confirmation.tool_name), *confirmation.asked ].compact
        lines = [ called.map { |name, value| "#{Slack::Mrkdwn.escape(name)}: #{Slack::Mrkdwn.escape(value)}" }.join("  ·  ").presence ].compact
        if confirmation.read_heading
          lines << confirmation.read_heading
          lines.concat(confirmation.read_rows.map { |label, said| "• #{Slack::Mrkdwn.escape(label)}: #{Slack::Mrkdwn.escape(said)}" })
        end
        return [] if lines.empty?

        [ { type: "context", elements: [ { type: "mrkdwn", text: lines.join("\n").truncate(Formatting::SECTION_TEXT_LIMIT) } ] } ]
      end
    end
  end
end
