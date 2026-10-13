module Slack
  module Messages
    # A workflow Halon made from a chat in a thread: when it runs, how it stands, how its last run went, with Run now and
    # Cancel (Turn off for one that repeats) and the workflow's page. Redrawn as it moves.
    module ChatWorkflow
      ACTIONS = {
        Workflow::ACTION_RUN_NOW => [ "Run now", Identifiers::CHAT_WORKFLOW_RUN_NOW ],
        Workflow::ACTION_CANCEL => [ "Cancel", Identifiers::CHAT_WORKFLOW_STOP ],
        Workflow::ACTION_TURN_OFF => [ "Turn off", Identifiers::CHAT_WORKFLOW_STOP ]
      }.freeze

      def self.build(workflow)
        blocks = [
          { type: "section", text: { type: "mrkdwn", text: ":repeat:  *#{Mrkdwn.escape(workflow.name)}*" } },
          { type: "context", elements: [ { type: "mrkdwn", text: Mrkdwn.escape(standing(workflow)) } ] }
        ]
        elements = offered(workflow) + page_button(workflow)
        blocks << { type: "actions", elements: elements } if elements.any?
        blocks
      end

      def self.fallback(workflow) = "#{workflow.name}: #{standing(workflow)}"

      # When it runs and how it last went, in a line.
      def self.standing(workflow)
        run = workflow.last_chat_run
        last = run && " Last run #{run.status.humanize(capitalize: false)}#{" (#{run.error.truncate(120)})" if run.error.present?}."
        return "It waits for a workspace admin to publish it." unless workflow.live?
        return "Done.#{last}" if workflow.done?
        return "Off.#{last}" unless workflow.enabled?

        "#{workflow.trigger_words}.#{last}"
      end

      # Only what a workflow offers at all is drawn. Who may press it is decided when it is pressed.
      def self.offered(workflow)
        actions = [ Workflow::ACTION_RUN_NOW ]
        actions << workflow.stop_action if workflow.live? && workflow.enabled? && !workflow.done?
        actions.filter_map do |action|
          next if action == Workflow::ACTION_RUN_NOW && workflow.start_blocked_reason

          label, action_id = ACTIONS.fetch(action)
          button = { type: "button", text: { type: "plain_text", text: label }, action_id: action_id, value: workflow.id }
          next button unless action_id == Identifiers::CHAT_WORKFLOW_STOP

          button.merge(confirm: { title: { type: "plain_text", text: "#{label}?" }, text: { type: "plain_text", text: "#{workflow.name} will not run again on its own." },
                                  confirm: { type: "plain_text", text: label }, deny: { type: "plain_text", text: "Keep it" } })
        end
      end

      def self.page_button(workflow)
        url = DashboardUrl.workflow(workflow)
        url ? [ { type: "button", text: { type: "plain_text", text: "Open the workflow" }, url: url } ] : []
      end
    end
  end
end
