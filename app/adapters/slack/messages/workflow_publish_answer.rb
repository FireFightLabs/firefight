module Slack
  module Messages
    # How an admin answered a member's request to publish a workflow, to that member.
    module WorkflowPublishAnswer
      def self.build(request)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: "#{request.published_at ? ':white_check_mark:' : ':no_entry_sign:'}  *#{Mrkdwn.escape(title(request))}*" } },
          { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(next_step(request)) } ] }
        ]
        url = DashboardUrl.workflow(request.workflow)
        blocks << { type: "actions", elements: [ { type: "button", text: { type: "plain_text", text: "Open the workflow" }, url: url } ] } if url
        blocks
      end

      def self.fallback(request) = "#{title(request)}. #{next_step(request)}"

      def self.title(request)
        name = request.workflow.name
        request.published_at ? "#{request.answered_by_name} published #{name}" : "#{request.answered_by_name} did not publish #{name}"
      end

      def self.next_step(request)
        return "It runs #{request.workflow.trigger_words.downcase_first}, and anyone can run it by hand." if request.published_at

        "Your request was dismissed, so it stays a draft. Ask #{request.answered_by_name} directly if it is still needed."
      end
    end
  end
end
