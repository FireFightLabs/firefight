module Slack
  module Modals
    # Answers a coding agent's question. The agent carries on with what is written here.
    module CodeQuestionAnswer
      ANSWER_BLOCK = "answer_block".freeze
      ANSWER_INPUT = "answer_input".freeze

      def self.build(question)
        {
          type: "modal",
          callback_id: Identifiers::CODE_QUESTION_MODAL,
          private_metadata: ModalState.encode(code_question_id: question.id),
          title: { type: "plain_text", text: "Answer the agent" },
          submit: { type: "plain_text", text: "Send answer" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*The coding agent asks*\n#{Messages::CodeQuestion.quoted(question.question)}" } },
            {
              type: "input",
              block_id: ANSWER_BLOCK,
              element: { type: "plain_text_input", action_id: ANSWER_INPUT, multiline: true, max_length: CodeAgentQuestion::ANSWER_LIMIT },
              label: { type: "plain_text", text: "Your answer" },
              hint: { type: "plain_text", text: "The coding agent carries on with it." }
            }
          ]
        }
      end

      def self.answer(values) = values.dig(ANSWER_BLOCK, ANSWER_INPUT, "value").to_s.strip
    end
  end
end
