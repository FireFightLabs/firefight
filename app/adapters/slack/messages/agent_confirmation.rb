module Slack
  module Messages
    # The calls the agent paused on in a thread, each with its buttons until someone answers.
    module AgentConfirmation
      TITLE = ":raised_hand:  *Confirm before I go ahead*".freeze
      STATUS_LINES = {
        confirmed: ":white_check_mark: Confirmed", cancelled: ":no_entry_sign: Cancelled"
      }.freeze

      def self.build(conversation_id:, confirmations:)
        [ { type: "section", text: { type: "mrkdwn", text: TITLE } } ] +
          confirmations.flat_map { |confirmation| question_blocks(conversation_id, confirmation) }
      end

      def self.fallback(confirmations)
        "Waiting for you to confirm: #{confirmations.map(&:question).join(", ")}"
      end

      # The arguments came from the model, so they are escaped like any other outside text.
      def self.question_blocks(conversation_id, confirmation)
        details = confirmation.asked.map { |name, value| "#{name}: #{Slack::Mrkdwn.escape(value)}" }.join("  ·  ")
        blocks = [ { type: "section", text: { type: "mrkdwn", text: "*#{Slack::Mrkdwn.escape(confirmation.question)}*" } } ]
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: details } ] } if details.present?
        blocks << answer_block(conversation_id, confirmation)
      end

      def self.answer_block(conversation_id, confirmation)
        status_line = STATUS_LINES[confirmation.status]
        return { type: "context", elements: [ { type: "mrkdwn", text: status_line } ] } if status_line

        value = "#{conversation_id}:#{confirmation.tool_call_id}"
        { type: "actions", elements: [
          { type: "button", style: "primary", action_id: Identifiers::AGENT_CONFIRM,
            text: { type: "plain_text", text: "Confirm" }, value: value },
          { type: "button", action_id: Identifiers::AGENT_CANCEL,
            text: { type: "plain_text", text: "Cancel" }, value: value }
        ] }
      end
    end
  end
end
