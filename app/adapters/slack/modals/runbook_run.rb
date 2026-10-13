module Slack
  module Modals
    module RunbookRun
      INPUT_BLOCK_PREFIX = "runbook_input_".freeze
      INPUT_ACTION = "runbook_input_value".freeze
      TITLE = "Run runbook".freeze

      def self.build(incident_runbook)
        workflow = incident_runbook.runbook.workflow
        asked = Workflow::Trigger.inputs(workflow.live_version&.trigger)
        {
          type: "modal",
          callback_id: Identifiers::RUNBOOK_RUN_MODAL,
          private_metadata: ModalState.encode(incident_id: incident_runbook.incident_id, incident_runbook_id: incident_runbook.id),
          title: { type: "plain_text", text: TITLE },
          submit: { type: "plain_text", text: "Run" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: intro(incident_runbook.runbook, workflow) } },
            *(asked.any? ? asked.map { |input| input_block(input) } : [ { type: "context", elements: [ { type: "mrkdwn", text: "It asks nothing before it runs." } ] } ])
          ]
        }
      end

      def self.intro(runbook, workflow)
        "*Run #{Slack::Mrkdwn.escape(runbook.name)}*\nIt runs the #{Slack::Mrkdwn.escape(workflow.name)} workflow now, " \
          "as the workflow itself with only what an admin granted it."
      end

      def self.input_block(input)
        element = { type: "plain_text_input", action_id: INPUT_ACTION }
        element[:initial_value] = input["default"].to_s if input["default"].present?
        {
          type: "input",
          block_id: "#{INPUT_BLOCK_PREFIX}#{input['key']}",
          element: element,
          label: { type: "plain_text", text: input["question"].to_s.truncate(2000) }
        }
      end

      def self.inputs(values)
        values.to_h.each_with_object({}) do |(block_id, actions), answers|
          next unless block_id.to_s.start_with?(INPUT_BLOCK_PREFIX)

          answers[block_id.to_s.delete_prefix(INPUT_BLOCK_PREFIX)] = actions.to_h.dig(INPUT_ACTION, "value").to_s.strip
        end
      end

      def self.refused(message)
        {
          type: "modal",
          title: { type: "plain_text", text: TITLE },
          close: { type: "plain_text", text: "Close" },
          blocks: [ { type: "section", text: { type: "mrkdwn", text: "*It did not start.*\n#{Slack::Mrkdwn.escape(message)}" } } ]
        }
      end
    end
  end
end
