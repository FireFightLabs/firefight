module Slack
  module Modals
    module Reopen
      def self.build(incident, private_metadata: nil)
        {
          type: "modal",
          callback_id: Identifiers::REOPEN_INCIDENT_MODAL,
          notify_on_close: true,
          private_metadata: private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Reopen incident" },
          submit: { type: "plain_text", text: "Reopen incident" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" } },
            {
              type: "input",
              block_id: "reason_block",
              element: {
                type: "plain_text_input",
                action_id: "reason_input",
                multiline: true,
                placeholder: { type: "plain_text", text: "Why is this incident being reopened?" },
                max_length: 3000
              },
              label: { type: "plain_text", text: "Reason for reopening" },
              optional: true
            }
          ]
        }
      end
    end
  end
end
