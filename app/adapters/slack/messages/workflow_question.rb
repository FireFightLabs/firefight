module Slack
  module Messages
    # A workflow's question, in a direct message to each person it asked: the question, what they should know, then a
    # button per choice and Answer for a short form. When there is a form, the choices are picked in it too, so the
    # buttons are left for a question with choices alone. A Manual step's task reads the same way, with Done, which opens
    # its note's form when it collects one, and goes in a channel when anyone may do it. Once settled it says who
    # answered or did it, or that nobody did, and the buttons are gone. Every message links the run.
    module WorkflowQuestion
      def self.build(question)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{question.task? ? ':clipboard:' : ':question:'}  *#{Mrkdwn.escape(title(question))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(question.question)}*".truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        blocks << { type: "section", text: { type: "mrkdwn", text: CodeQuestion.quoted(question.details) } } if question.details.present?
        actions = [ *buttons(question), *run_button(question) ]
        blocks << { type: "actions", elements: actions } if actions.any?
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: question.open? ? waiting(question) : settled(question) } ] }
      end

      def self.fallback(question) = "#{title(question)}: #{question.question}".truncate(300)

      def self.title(question)
        name = question.run.workflow.name
        return "#{name} #{question.open? ? 'needs' : 'needed'} this done" if question.task?

        "#{name} #{question.open? ? 'asks' : 'asked'}"
      end

      def self.buttons(question)
        return [] unless question.open?
        return [ done_button(question) ] if question.task?
        return [ answer_button(question, "Answer") ] if question.form?

        question.choice_keys.each_with_index.map do |key, index|
          { type: "button", text: { type: "plain_text", text: question.choice_words(key).truncate(75) },
            action_id: Identifiers::WORKFLOW_QUESTION_CHOOSE_IDS.fetch(index), value: "#{question.id}:#{index}" }
        end
      end

      # Done finishes a task at once, or opens the form for the note it collects.
      def self.done_button(question)
        return answer_button(question, "Done") if question.form?

        { type: "button", style: "primary", text: { type: "plain_text", text: "Done" }, action_id: Identifiers::WORKFLOW_TASK_DONE, value: question.id }
      end

      def self.answer_button(question, words)
        { type: "button", style: "primary", text: { type: "plain_text", text: words }, action_id: Identifiers::WORKFLOW_QUESTION_ANSWER, value: question.id }
      end

      def self.run_button(question)
        url = DashboardUrl.workflow_run(question.run)
        url ? [ { type: "button", text: { type: "plain_text", text: "Open the run" }, url: url } ] : []
      end

      def self.waiting(question)
        due = Formatting.slack_time(question.due_at)
        return "#{assigned(question)}  ·  If it is not done by #{due}, the run goes on without it." if question.task?

        who = question.asked_members.map { |member| Mrkdwn.mention(member) }.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")
        "#{who.presence || 'The people it asked'} can answer, and the first answer counts.  ·  If nobody answers by #{due}, the run goes on without one."
      end

      def self.assigned(question)
        return "Anyone can mark it done." if question.open_to_anyone?

        "Assigned to #{question.asked_members.map { |member| Mrkdwn.mention(member) }.to_sentence}."
      end

      def self.settled(question)
        return settled_task(question) if question.task?

        if question.answered?
          said = Mrkdwn.escape(question.answer_words.to_s).gsub("\n", "  ·  ")
          return "*#{Mrkdwn.escape(question.answered_by&.actor_display_name || 'Someone')}* answered: #{said}".truncate(Formatting::SECTION_TEXT_LIMIT)
        end

        question.due_at <= Time.current ? "Nobody answered in time, so the run went on without an answer." : "The run stopped waiting before anyone answered."
      end

      def self.settled_task(question)
        if question.answered?
          who = "*#{Mrkdwn.escape(question.answered_by&.actor_display_name || 'Someone')}* marked it done"
          note = question.answer_words.presence
          return (note ? "#{who}: #{Mrkdwn.escape(note).gsub("\n", '  ·  ')}" : "#{who}.").truncate(Formatting::SECTION_TEXT_LIMIT)
        end

        question.due_at <= Time.current ? "Nobody marked it done in time, so the run went on without it." : "The run stopped waiting before it was done."
      end
    end
  end
end
