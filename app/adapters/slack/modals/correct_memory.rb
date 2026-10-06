module Slack
  module Modals
    # Says what is right instead of a memory. The old wording is kept as rejected, and the correction replaces it as
    # confirmed by whoever wrote it.
    module CorrectMemory
      CORRECTION_BLOCK = "correction_block".freeze
      CORRECTION_INPUT = "correction_input".freeze
      REASON_BLOCK = "reason_block".freeze
      REASON_INPUT = "reason_input".freeze

      # memory is a MemoryPostService::ShownMemory.
      def self.build(post_id:, memory:)
        {
          type: "modal",
          callback_id: Identifiers::MEMORY_CORRECT_MODAL,
          private_metadata: ModalState.encode(memory_post_id: post_id, memory_id: memory.id),
          title: { type: "plain_text", text: "Correct memory" },
          submit: { type: "plain_text", text: "Correct" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*Halon remembers*\n> #{Slack::Mrkdwn.escape(memory.text).gsub("\n", "\n> ")}" } },
            {
              type: "input",
              block_id: CORRECTION_BLOCK,
              element: { type: "plain_text_input", action_id: CORRECTION_INPUT, multiline: true, max_length: Chat::Memory::TEXT_LIMIT },
              label: { type: "plain_text", text: "What is right instead" },
              hint: { type: "plain_text", text: "One plain sentence about the setup. Halon uses it from now on, confirmed by you." }
            },
            {
              type: "input",
              block_id: REASON_BLOCK,
              optional: true,
              element: { type: "plain_text_input", action_id: REASON_INPUT, max_length: Chat::Memory::TEXT_LIMIT },
              label: { type: "plain_text", text: "Why it was wrong" }
            }
          ]
        }
      end

      def self.values(values)
        { correction: values.dig(CORRECTION_BLOCK, CORRECTION_INPUT, "value").to_s.strip, reason: values.dig(REASON_BLOCK, REASON_INPUT, "value").to_s.strip }
      end
    end
  end
end
