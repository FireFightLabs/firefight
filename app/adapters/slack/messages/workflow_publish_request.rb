module Slack
  module Messages
    # A member asking an admin, by direct message, to publish a workflow they built or changed, with what its own identity
    # will be able to do once published. Publish makes it live and grants that, the same as on the workflow's page. Once
    # published or dismissed it says by whom.
    module WorkflowPublishRequest
      REACH_SHOWN = 8

      def self.build(request)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":rocket:  *#{Mrkdwn.escape(headline(request))}*" } },
          { type: "divider" },
          { type: "section", text: { type: "mrkdwn", text: Mrkdwn.escape(body(request)).truncate(Formatting::SECTION_TEXT_LIMIT) } }
        ]
        settled = settled_line(request)
        return blocks << { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(settled) } ] } if settled

        elements = [ { type: "button", text: { type: "plain_text", text: "Publish" }, action_id: Identifiers::WORKFLOW_PUBLISH_REQUEST_PUBLISH,
                       value: request.id, style: "primary" } ]
        url = DashboardUrl.workflow(request.workflow)
        elements << { type: "button", text: { type: "plain_text", text: "Open the workflow" }, url: url } if url
        blocks << { type: "actions", elements: elements }
      end

      def self.fallback(request) = headline(request)

      def self.headline(request) = "#{request.requester.display_name} asks you to publish #{request.workflow.name}"

      def self.body(request)
        workflow = request.workflow
        reach = workflow.missing_reach(request.version).map(&:label)
        lines = [ "#{workflow.trigger_words}." ]
        if reach.any?
          shown = reach.first(REACH_SHOWN)
          shown << "#{reach.size - REACH_SHOWN} more" if reach.size > REACH_SHOWN
          lines << "Publishing also lets it #{shown.map { |label| label.downcase_first }.to_sentence}."
        end
        lines.join("\n")
      end

      def self.settled_line(request)
        who = request.answered_by_name
        return "Published by #{who}." if request.published_at

        "Dismissed by #{who}." if request.dismissed_at
      end
    end
  end
end
