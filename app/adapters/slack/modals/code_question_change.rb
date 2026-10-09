module Slack
  module Modals
    # Changes the answer to a coding agent's question while its change is still written: another of its options, or the
    # person's own words. The agent is sent the new answer in place of the earlier one.
    module CodeQuestionChange
      OPTION_BLOCK = "option_block".freeze
      OPTION_INPUT = "option_input".freeze
      ANSWER_BLOCK = "answer_block".freeze
      ANSWER_INPUT = "answer_input".freeze
      LABEL_SHOWN = 75

      Values = Data.define(:option, :answer)

      def self.build(question)
        {
          type: "modal",
          callback_id: Identifiers::CODE_QUESTION_CHANGE_MODAL,
          private_metadata: ModalState.encode(code_question_id: question.id),
          title: { type: "plain_text", text: "Change the answer" },
          submit: { type: "plain_text", text: "Submit" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*The coding agent asked*\n#{Messages::CodeQuestion.quoted(question.question)}" } },
            *Messages::CodeQuestion.option_blocks(question),
            { type: "context", elements: [ { type: "mrkdwn", text: "The answer now: #{Mrkdwn.escape(question.current_answer.to_s)}".truncate(Messages::Formatting::SECTION_TEXT_LIMIT) } ] },
            *option_input(question),
            {
              type: "input",
              block_id: ANSWER_BLOCK,
              optional: true,
              element: { type: "plain_text_input", action_id: ANSWER_INPUT, multiline: true, max_length: CodeAgentQuestion::ANSWER_LIMIT },
              label: { type: "plain_text", text: question.choices.empty? ? "Your new answer" : "Or write your own answer" },
              hint: { type: "plain_text", text: "The coding agent is sent this in place of the earlier answer." }
            }
          ]
        }
      end

      def self.option_input(question)
        return [] if question.choices.empty?

        [ {
          type: "input",
          block_id: OPTION_BLOCK,
          optional: true,
          element: {
            type: "radio_buttons", action_id: OPTION_INPUT,
            options: question.choices.each_with_index.map { |choice, index| { text: { type: "plain_text", text: choice.label.truncate(LABEL_SHOWN) }, value: index.to_s } }
          },
          label: { type: "plain_text", text: "Pick another option" }
        } ]
      end

      def self.values(values)
        picked = values.dig(OPTION_BLOCK, OPTION_INPUT, "selected_option", "value")
        Values.new(option: (Integer(picked, exception: false) if picked.present?), answer: values.dig(ANSWER_BLOCK, ANSWER_INPUT, "value").to_s.strip)
      end
    end
  end
end
