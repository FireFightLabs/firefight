module Slack
  module Messages
    # A workflow's question, in a direct message to each person it asked: the question, what they should know, then a
    # button per choice and Answer for a short form. When there is a form, the choices are picked in it too, so the
    # buttons are left for a question with choices alone. Once settled it says who answered and how, or that nobody did,
    # and the buttons are gone. Every message links the run.
    module WorkflowQuestion
      def self.build(question)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":question:  *#{Mrkdwn.escape(title(question))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(question.question)}*".truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: CodeQuestion.quoted(question.details) } } if question.details.present?
        actions = [ *buttons(question), *run_button(question) ]
        blocks << { type: "actions", elements: actions } if actions.any?
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: question.open? ? waiting(question) : settled(question) } ] }
      end

      def self.fallback(question) = "#{title(question)}: #{question.question}".truncate(300)

      def self.title(question) = "#{question.run.workflow.name} #{question.open? ? 'asks' : 'asked'}"

      def self.buttons(question)
        return [] unless question.open?
        return [ answer_button(question) ] if question.form?

        question.choices.each_with_index.map do |choice, index|
          { type: "button", text: { type: "plain_text", text: question.choice_words(choice).truncate(75) },
            action_id: Identifiers::WORKFLOW_QUESTION_CHOOSE_IDS.fetch(index), value: "#{question.id}:#{index}" }
        end
      end

      def self.answer_button(question)
        { type: "button", style: "primary", text: { type: "plain_text", text: "Answer" }, action_id: Identifiers::WORKFLOW_QUESTION_ANSWER, value: question.id }
      end

      def self.run_button(question)
        url = DashboardUrl.workflow_run(question.run)
        url ? [ { type: "button", text: { type: "plain_text", text: "Open the run" }, url: url } ] : []
      end

      def self.waiting(question)
        who = question.asked_members.map { |member| Mrkdwn.mention(member) }.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
        "#{who.presence || 'The people it asked'} can answer, and the first answer counts.  ·  If nobody answers by " \
          "#{Formatting.slack_time(question.due_at)}, the run goes on without one."
      end

      def self.settled(question)
        if question.answered?
          said = Mrkdwn.escape(question.answer_words.to_s).gsub("\n", "  ·  ")
          return "*#{Mrkdwn.escape(question.answered_by&.actor_display_name || 'Someone')}* answered: #{said}".truncate(Formatting::SECTION_TEXT_LIMIT)
        end

        question.due_at <= Time.current ? "Nobody answered in time, so the run went on without an answer." : "The run stopped waiting before anyone answered."
      end
    end
  end
end
