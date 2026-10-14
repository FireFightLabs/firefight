module Slack
  module Modals
    # Answers a workflow's question that has a short form: one of its choices when it has any, and each field. The run
    # carries on with what is sent here.
    module WorkflowQuestionAnswer
      CHOICE_BLOCK = "choice_block".freeze
      CHOICE_INPUT = "choice_input".freeze
      FIELD_BLOCK_PREFIX = "field_".freeze
      FIELD_INPUT = "field_input".freeze

      def self.build(question)
        {
          type: "modal",
          callback_id: Identifiers::WORKFLOW_QUESTION_MODAL,
          private_metadata: ModalState.encode(workflow_question_id: question.id),
          title: { type: "plain_text", text: "Answer" },
          submit: { type: "plain_text", text: "Send answer" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(question.run.workflow.name)} asks*\n#{Messages::CodeQuestion.quoted(question.question)}" } },
            *choice_block(question),
            *question.fields.map { |field| field_block(field) }
          ]
        }
      end

      def self.choice_block(question)
        return [] if question.choices.empty?

        options = question.choices.map { |choice| { text: { type: "plain_text", text: question.choice_words(choice).truncate(75) }, value: choice } }
        [ { type: "input", block_id: CHOICE_BLOCK, label: { type: "plain_text", text: "Your choice" },
            element: { type: "radio_buttons", action_id: CHOICE_INPUT, options: options } } ]
      end

      def self.field_block(field)
        {
          type: "input",
          block_id: "#{FIELD_BLOCK_PREFIX}#{field[Workflow::Run::Question::FIELD_NAME]}",
          label: { type: "plain_text", text: field[Workflow::Run::Question::FIELD_LABEL].to_s.truncate(2_000) },
          element: { type: "plain_text_input", action_id: FIELD_INPUT, multiline: true, max_length: Workflow::Run::Question::ANSWER_LIMIT }
        }
      end

      def self.answer(values)
        fields = values.to_h.filter_map do |block_id, inputs|
          next unless block_id.to_s.start_with?(FIELD_BLOCK_PREFIX)

          [ block_id.to_s.delete_prefix(FIELD_BLOCK_PREFIX), inputs.dig(FIELD_INPUT, "value").to_s.strip ]
        end
        { choice: values.dig(CHOICE_BLOCK, CHOICE_INPUT, "selected_option", "value"), values: fields.to_h }
      end

      # The block a refusal is shown under: the choice when there is one, otherwise the form's first field.
      def self.error_block(question)
        question.choices.any? ? CHOICE_BLOCK : "#{FIELD_BLOCK_PREFIX}#{question.fields.first.to_h[Workflow::Run::Question::FIELD_NAME]}"
      end
    end
  end
end
