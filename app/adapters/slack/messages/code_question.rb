module Slack
  module Messages
    # A question a coding agent asked while it writes a change, in the thread of the chat or fix the change was asked in:
    # the question in a line, then each option with what it leads to and the recommended one marked with why. A button
    # per option answers in one click, and Something else opens a form for an answer in the person's own words. Only the
    # person the change runs as can answer. Once settled it says who answered and how, and the option buttons are gone.
    # While the change is still written, Change answer opens a form for another option or the person's own words, and a
    # changed answer says what it changed to and who changed it.
    module CodeQuestion
      def self.build(question)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":question:  *#{title(question)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(question.question)}*".truncate(Formatting::SECTION_TEXT_LIMIT) } },
          *option_blocks(question)
        ]
        return settled_blocks(blocks, question) unless question.open?

        blocks << { type: "actions", elements: [ *option_buttons(question), something_else(question, primary: question.choices.empty?) ] }
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: waiting(question) } ] }
      end

      def self.fallback(question) = "#{title(question)}: #{question.question}"

      def self.title(question) = question.open? ? "The coding agent asks" : "The coding agent asked"

      def self.quoted(text) = Mrkdwn.escape(text.to_s).lines.map { |line| "> #{line.chomp}" }.join("\n").truncate(Formatting::SECTION_TEXT_LIMIT)

      # Each option in a line of its own: the label in bold, Recommended with why on the agent's pick, what it leads to below.
      def self.option_blocks(question)
        question.choices.each_with_index.map do |choice, index|
          mark = index == question.recommended ? "  ·  _Recommended. #{Mrkdwn.escape(question.recommended_reason.to_s)}_" : ""
          picked = index == question.current_chosen && !question.open? ? ":white_check_mark:  " : ""
          { type: "section", text: { type: "mrkdwn", text: "#{picked}*#{Mrkdwn.escape(choice.label)}*#{mark}\n#{Mrkdwn.escape(choice.consequence)}".truncate(Formatting::SECTION_TEXT_LIMIT) } }
        end
      end

      def self.option_buttons(question)
        question.choices.each_with_index.map do |choice, index|
          button = { type: "button", text: { type: "plain_text", text: choice.label.truncate(75) }, action_id: Identifiers::CODE_QUESTION_CHOOSE_IDS.fetch(index),
                     value: "#{question.id}:#{index}" }
          index == question.recommended ? button.merge(style: "primary") : button
        end
      end

      def self.something_else(question, primary:)
        button = { type: "button", text: { type: "plain_text", text: question.choices.empty? ? "Answer" : "Something else" },
                   action_id: Identifiers::CODE_QUESTION_ANSWER, value: question.id }
        primary ? button.merge(style: "primary") : button
      end

      def self.settled_blocks(blocks, question)
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: settled(question) } ] }
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: changed(question) } ] } if question.changed?
        blocks << { type: "actions", elements: [ change_button(question) ] } if question.changeable?
        blocks
      end

      def self.changed(question)
        "Changed to *#{Mrkdwn.escape(question.changed_to.to_s)}* by *#{Mrkdwn.escape(question.changed_by_name.to_s)}*".truncate(Formatting::SECTION_TEXT_LIMIT)
      end

      def self.change_button(question)
        { type: "button", text: { type: "plain_text", text: "Change answer" }, action_id: Identifiers::CODE_QUESTION_CHANGE, value: question.id }
      end

      def self.waiting(question)
        asker = question.session.principal
        who = asker ? Mrkdwn.mention(asker) : "the person who asked for the change"
        due = Formatting.slack_time(question.answer_due_at)
        "Only #{who} can answer.  ·  If nobody answers by #{due}, #{question.timeout_outcome}."
      end

      def self.settled(question)
        if question.answered?
          said = question.chosen_option ? "chose #{Mrkdwn.escape(question.chosen_option.label)}" : "answered: #{Mrkdwn.escape(question.answer.to_s)}"
          return "*#{Mrkdwn.escape(question.answered_by_name.to_s)}* #{said}".truncate(Formatting::SECTION_TEXT_LIMIT)
        end
        return "Nobody answered in time, so the change went with the recommendation, #{Mrkdwn.escape(question.recommended_option.label)}." if question.defaulted?
        return "Nobody answered in time, so the change stopped." if question.expired?

        "The change ended before anyone answered."
      end
    end
  end
end
