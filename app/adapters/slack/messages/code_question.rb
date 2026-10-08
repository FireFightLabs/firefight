module Slack
  module Messages
    # A question a coding agent asked while it writes a change, in the thread of the chat or fix the change was asked in.
    # Answer opens a form, which only the person the change runs as can send. Once settled it says who answered and how,
    # and the button is gone.
    module CodeQuestion
      def self.build(question)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":question:  *#{title(question)}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: quoted(question.question) } }
        ]
        return blocks << { type: "context", elements: [ { type: "mrkdwn", text: settled(question) } ] } unless question.open?

        blocks << { type: "actions", elements: [
          { type: "button", text: { type: "plain_text", text: "Answer" }, action_id: Identifiers::CODE_QUESTION_ANSWER, value: question.id, style: "primary" }
        ] }
        blocks << { type: "context", elements: [ { type: "mrkdwn", text: waiting(question) } ] }
      end

      def self.fallback(question) = "#{title(question)}: #{question.question}"

      def self.title(question) = question.open? ? "The coding agent asks" : "The coding agent asked"

      def self.quoted(text) = Mrkdwn.escape(text.to_s).lines.map { |line| "> #{line.chomp}" }.join("\n").truncate(2_900)

      def self.waiting(question)
        asker = question.session.principal
        who = asker ? Mrkdwn.mention(asker) : "the person who asked for the change"
        "Only #{who} can answer.  ·  If nobody answers by <!date^#{question.answer_due_at.to_i}^{time}|#{question.answer_due_at.utc.strftime('%H:%M UTC')}>, the change stops."
      end

      def self.settled(question)
        return "*#{Mrkdwn.escape(question.answered_by_name.to_s)} answered:* #{Mrkdwn.escape(question.answer.to_s)}".truncate(2_900) if question.answered?
        return "Nobody answered in time, so the change stopped." if question.expired?

        "The change ended before anyone answered."
      end
    end
  end
end
