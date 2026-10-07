module Slack
  module Messages
    # How an admin answered a member's request for a pack. Direct is to the member, otherwise it is a short note in the
    # thread of the chat where the change was refused, naming them. Title and a line of what to do next, no body.
    module PackAnswer
      def self.build(request, direct: false)
        [
          { type: "section", text: { type: "mrkdwn", text: "#{request.given_at ? ':white_check_mark:' : ':no_entry_sign:'}  *#{Mrkdwn.escape(title(request, direct))}*" } },
          { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(next_step(request, direct)) } ] }
        ]
      end

      def self.fallback(request, direct: false) = "#{title(request, direct)}. #{next_step(request, direct)}"

      def self.title(request, direct)
        who = request.answered_by_name
        to = direct ? "you" : request.requester.display_name
        request.given_at ? "#{who} gave #{to} #{request.role.name}" : "#{who} did not give #{to} #{request.role.name}"
      end

      def self.next_step(request, direct)
        return direct ? "You can ask Halon again." : "Ask Halon again to make the change." if request.given_at

        "The request was dismissed, so the change still cannot be made. Ask #{request.answered_by_name} directly if it is still needed."
      end
    end
  end
end
