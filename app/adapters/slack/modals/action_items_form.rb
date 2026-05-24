module Slack
  module Modals
    # The "Create action" and "Create follow-up" modals. Same shape — only
    # the title, callback_id, and emoji hint differ by kind.
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

      def self.build(incident, kind:, private_metadata: nil)
        cfg = KINDS.fetch(kind)
        metadata = private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id)
        # When this modal is launched from a reaction shortcut the caller
        # encodes the source message text in the private_metadata so we can
        # prefill the description.
        parsed_metadata = JSON.parse(metadata) rescue {}
        initial_description = parsed_metadata["source_message_text"]

        description_element = {
          type: "plain_text_input",
          action_id: "description_input",
          multiline: true,
          placeholder: { type: "plain_text", text: "Write something" },
          max_length: 3000
        }
        description_element[:initial_value] = initial_description if initial_description.present?

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
