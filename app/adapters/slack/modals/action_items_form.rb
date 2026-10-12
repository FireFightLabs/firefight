module Slack
  module Modals
    module ActionItemsForm
      KINDS = {
        action: {
          title: "Create action",
          callback_id: -> { Identifiers::CREATE_ACTION_MODAL },
          hint: ":bulb: You can create an action from a Slack message by reacting with the :boom: emoji"
        },
        followup: {
          title: "Create follow-up",
          callback_id: -> { Identifiers::CREATE_FOLLOWUP_MODAL },
          hint: ":bulb: You can create a follow-up from a Slack message by reacting with the :arrow_forward: emoji"
        }
      }.freeze

      DESCRIPTION_LIMIT = 3000

      # description is what the field starts with, such as the message a reaction was added to.
      def self.build(incident, kind:, private_metadata: nil, description: nil)
        cfg = KINDS.fetch(kind)
        metadata = private_metadata || ModalState.encode(incident_id: incident.id)

        description_element = {
          type: "plain_text_input",
          action_id: "description_input",
          multiline: true,
          placeholder: { type: "plain_text", text: "Write something" },
          max_length: DESCRIPTION_LIMIT
        }
        description_element[:initial_value] = description.truncate(DESCRIPTION_LIMIT) if description.present?

        {
          type: "modal",
          callback_id: cfg[:callback_id].call,
          private_metadata: metadata,
          title: { type: "plain_text", text: cfg[:title] },
          submit: { type: "plain_text", text: "Create" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            {
              type: "input",
              block_id: "description_block",
              element: description_element,
              label: { type: "plain_text", text: "Description" }
            },
            {
              type: "input",
              block_id: "assignee_block",
              element: {
                type: "users_select",
                action_id: "assignee_select",
                placeholder: { type: "plain_text", text: "Pick an option" }
              },
              label: { type: "plain_text", text: "Who's picking it up?" },
              optional: true
            },
            {
              type: "context",
              elements: [ { type: "mrkdwn", text: cfg[:hint] } ]
            }
          ]
        }
      end
    end
  end
end
