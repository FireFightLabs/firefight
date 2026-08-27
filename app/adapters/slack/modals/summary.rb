module Slack
  module Modals
    module Summary
      def self.build(incident, private_metadata: nil)
        initial_value = incident.summary.present? ? { initial_value: incident.summary } : {}
        metadata = private_metadata || ModalState.encode(incident_id: incident.id)

        {
          type: "modal",
          callback_id: Identifiers::UPDATE_SUMMARY_MODAL,
          notify_on_close: true,
          private_metadata: metadata,
          title: { type: "plain_text", text: "Update Summary" },
          submit: { type: "plain_text", text: "Save" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            {
              type: "section",
              text: { type: "mrkdwn", text: "*#{incident.identifier}*: #{incident.name || 'Untitled Incident'}" }
            },
            {
              type: "input",
              block_id: "summary_block",
              element: {
                type: "plain_text_input",
                action_id: "summary_input",
                multiline: true,
                placeholder: { type: "plain_text", text: "What is your current understanding of the incident and its impact?" },
                max_length: 3000
              }.merge(initial_value),
              label: { type: "plain_text", text: "Summary" },
              hint: { type: "plain_text", text: "Describe what happened, the impact, and the current state. It's fine to go into detail." },
              optional: true
            }
          ]
        }
      end
    end
  end
end
