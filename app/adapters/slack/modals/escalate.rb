module Slack
  module Modals
    module Escalate
      def self.build(incident, private_metadata: nil)
        {
          type: "modal",
          callback_id: Identifiers::ESCALATE_INCIDENT_MODAL,
          notify_on_close: true,
          private_metadata: private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Escalate incident" },
          submit: { type: "plain_text", text: "Escalate" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" } },
            {
              type: "input",
              block_id: "escalate_to_block",
              element: {
                type: "users_select",
                action_id: "escalate_to_select",
                placeholder: { type: "plain_text", text: "Select a person" }
              },
              label: { type: "plain_text", text: "Who should we escalate to?" }
            },
            {
              type: "input",
              block_id: "reason_block",
              element: {
                type: "plain_text_input",
                action_id: "reason_input",
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
