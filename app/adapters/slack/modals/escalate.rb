module Slack
  module Modals
    module Escalate
      def self.build(incident, private_metadata: nil)
        {
          type: "modal",
          callback_id: Identifiers::ESCALATE_INCIDENT_MODAL,
          notify_on_close: true,
          private_metadata: private_metadata || ModalState.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Escalate incident" },
          submit: { type: "plain_text", text: "Escalate" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" } },
            {
              type: "input",
              block_id: Identifiers::ESCALATE_TO_BLOCK,
              element: {
                type: "users_select",
                action_id: Identifiers::ESCALATE_TO_SELECT,
                placeholder: { type: "plain_text", text: "Select a person" }
              },
              label: { type: "plain_text", text: "Who should we escalate to?" }
            },
            {
              type: "input",
              block_id: Identifiers::REASON_BLOCK,
              element: {
                type: "plain_text_input",
                action_id: Identifiers::REASON_INPUT,
                multiline: true,
                placeholder: { type: "plain_text", text: "Add context for the escalation" },
                max_length: 3000
              },
              label: { type: "plain_text", text: "Reason" },
              optional: true
            }
          ]
        }
      end
    end
  end
end
