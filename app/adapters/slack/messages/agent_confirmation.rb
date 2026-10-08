module Slack
  module Messages
    # The calls the agent paused on in a thread, each with its buttons until someone answers.
    module AgentConfirmation
      TITLE = ":raised_hand:  *Confirm before I go ahead*".freeze
      STATUS_LINES = {
        confirmed: ":white_check_mark: Confirmed", cancelled: ":no_entry_sign: Cancelled",
        withdrawn: ":heavy_minus_sign: Withdrawn. Something else was asked first, so this was not run."
      }.freeze

      def self.build(conversation_id:, confirmations:)
        [ { type: "section", text: { type: "mrkdwn", text: TITLE } } ] +
          confirmations.flat_map { |confirmation| question_blocks(conversation_id, confirmation) }
      end

      def self.fallback(confirmations)
        "Waiting for you to confirm: #{confirmations.map { |confirmation| confirmation.target ? confirmation.question : confirmation.intent || confirmation.question }.join(", ")}"
      end

      # The arguments came from the model, so they are escaped like any other outside text. A call through a connection
      # leads with what it reaches, worked out from the tool, then the call, and the agent's sentence follows with what the
      # tool was given, since the agent's words can name another account than the one the tool reaches. Any other call
      # leads with the agent's sentence when it wrote one, and the tool and what it was given follow.
      def self.question_blocks(conversation_id, confirmation)
        details = confirmation.asked.map { |name, value| "#{name}: #{Slack::Mrkdwn.escape(value)}" }
        if confirmation.target
          details.unshift(Slack::Mrkdwn.escape(confirmation.intent)) if confirmation.intent
          text = "*#{Slack::Mrkdwn.escape(confirmation.target)}*\n#{Slack::Mrkdwn.escape(confirmation.call)}"
        else
          details.unshift(Slack::Mrkdwn.escape(confirmation.question.delete_suffix("?"))) if confirmation.intent
          text = "*#{Slack::Mrkdwn.escape(confirmation.intent || confirmation.question)}*"
        end
        blocks = [ { type: "section", text: { type: "mrkdwn", text: text } } ]
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: details.join("  ·  ") } ] } if details.any?
        blocks << answer_block(conversation_id, confirmation)
      end

      def self.answer_block(conversation_id, confirmation)
        status_line = STATUS_LINES[confirmation.status]
        return { type: "context", elements: [ { type: "mrkdwn", text: status_line } ] } if status_line

        value = "#{conversation_id}:#{confirmation.tool_call_id}"
        { type: "actions", elements: [
          { type: "button", style: "primary", action_id: Identifiers::AGENT_CONFIRM,
            text: { type: "plain_text", text: "Confirm" }, value: value },
          { type: "button", action_id: Identifiers::AGENT_ALLOW_FOR_CHAT,
            text: { type: "plain_text", text: "Allow for this chat" }, value: value },
          { type: "button", action_id: Identifiers::AGENT_CANCEL,
            text: { type: "plain_text", text: "Cancel" }, value: value }
        ] }
      end
    end
  end
end
