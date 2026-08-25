module Slack
  module Modals
    module Lead
      def self.build(incident)
        element = {
          type: "users_select",
          action_id: "lead_select",
          placeholder: { type: "plain_text", text: "Select a person" }
        }
        element[:initial_user] = incident.lead.platform_user_id if incident.lead

        {
          type: "modal",
          callback_id: Identifiers::SET_LEAD_MODAL,
          private_metadata: ModalState.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Set Incident Lead" },
          submit: { type: "plain_text", text: "Assign" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            {
              type: "section",
              text: { type: "mrkdwn", text: "*#{incident.identifier}*: #{incident.name || 'Untitled Incident'}" }
            },
            {
              type: "input",
              block_id: "lead_block",
              element: element,
              label: { type: "plain_text", text: "Incident Lead" },
              hint: { type: "plain_text", text: "The lead coordinates the incident response and provides regular updates." }
            }
          ]
        }
      end
    end
  end
end
