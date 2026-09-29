module Slack
  module Messages
    # What Halon learned from an ended incident, each lesson with its buttons until someone decides on it.
    module LearnedMemories
      INTRO = "Saved for the next incident. Confirm what is right, so Halon trusts it, or mark it not right.".freeze
      DECIDED = {
        Chat::Memory::STATE_CONFIRMED => ":white_check_mark: Confirmed", Chat::Memory::STATE_REJECTED => ":no_entry_sign: Marked not right"
      }.freeze

      def self.build(incident_id:, incident_identifier:, memories:)
        [
          { type: "section", text: { type: "mrkdwn", text: ":brain:  *What Halon learned from #{incident_identifier}*" } },
          { type: "context", elements: [ { type: "mrkdwn", text: INTRO } ] },
          { type: "divider" }
        ] + memories.flat_map { |memory| memory_blocks(incident_id, memory) }
      end

      def self.fallback(incident_identifier, memories)
        "What Halon learned from #{incident_identifier}: #{memories.map(&:text).join(' ')}"
      end

      # The lesson came from a model, so it is escaped like any other outside text.
      def self.memory_blocks(incident_id, memory)
        about = memory.about.present? ? "About #{Slack::Mrkdwn.escape(memory.about)}" : "About the whole workspace"
        [
          { type: "section", text: { type: "mrkdwn", text: Slack::Mrkdwn.escape(memory.text) } },
          { type: "context", elements: [ { type: "mrkdwn", text: about } ] },
          decision_block(incident_id, memory)
        ]
      end

      def self.decision_block(incident_id, memory)
        decided = DECIDED[memory.state]
        return { type: "context", elements: [ { type: "mrkdwn", text: [ decided, ("by #{Slack::Mrkdwn.escape(memory.decided_by)}" if memory.decided_by) ].compact.join(" ") } ] } if decided

        value = "#{incident_id}:#{memory.id}"
        { type: "actions", elements: [
          { type: "button", style: "primary", action_id: Identifiers::MEMORY_CONFIRM, text: { type: "plain_text", text: "Confirm" }, value: value },
          { type: "button", action_id: Identifiers::MEMORY_REJECT, text: { type: "plain_text", text: "Not right" }, value: value }
        ] }
      end
    end
  end
end
