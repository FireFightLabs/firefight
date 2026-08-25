module Slack
  module Modals
    module AttachRunbook
      MAX_OPTIONS = 100

      def self.build(incident, runbooks)
        {
          type: "modal",
          callback_id: Identifiers::ATTACH_RUNBOOK_MODAL,
          private_metadata: ModalState.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Attach runbook" },
          submit: { type: "plain_text", text: "Attach" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            {
              type: "input",
              block_id: "runbook_block",
              element: {
                type: "static_select",
                action_id: "runbook_select",
                placeholder: { type: "plain_text", text: "Pick a runbook" },
                options: options(runbooks)
              },
              label: { type: "plain_text", text: "Runbook" }
            }
          ]
        }
      end

      def self.options(runbooks)
        runbooks.first(MAX_OPTIONS).map do |runbook|
          option = {
            text: { type: "plain_text", text: runbook.name.truncate(75) },
            value: runbook.slug
          }
          if runbook.summary.present?
            option[:description] = { type: "plain_text", text: runbook.summary.truncate(75) }
          end
          option
        end
      end
    end
  end
end
