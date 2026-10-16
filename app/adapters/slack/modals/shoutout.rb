module Slack
  module Modals
    module Shoutout
      def self.build(incident)
        {
          type: "modal",
          callback_id: Identifiers::SHOUTOUT_MODAL,
          private_metadata: ModalState.encode(incident_id: incident.id),
          title: { type: "plain_text", text: "Give a shoutout" },
          submit: { type: "plain_text", text: "Send" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            {
              type: "input",
              block_id: Identifiers::SHOUTOUT_RECIPIENT_BLOCK,
              element: {
                type: "users_select",
                action_id: Identifiers::SHOUTOUT_RECIPIENT_SELECT,
                placeholder: { type: "plain_text", text: "Who deserves recognition?" }
              },
              label: { type: "plain_text", text: "Shoutout to" }
            },
            {
              type: "input",
              block_id: Identifiers::SHOUTOUT_MESSAGE_BLOCK,
              element: {
                type: "plain_text_input",
                action_id: Identifiers::SHOUTOUT_MESSAGE_INPUT,
                multiline: true,
                placeholder: { type: "plain_text", text: "What did they do that was awesome?" },
                max_length: 500
              },
              label: { type: "plain_text", text: "Message" }
            }
          ]
        }
      end
    end
  end
end
