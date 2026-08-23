module Slack
  module Modals
    # The "Create action" and "Create follow-up" modals. Same shape, only
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

      ACTION_TYPES = {
        action: IncidentAction::ACTION_TYPE_ACTION,
        followup: IncidentAction::ACTION_TYPE_FOLLOWUP
      }.freeze

      # The callback_id names the kind, so the submission handler does not
      # have to be a separate class per kind.
      def self.kind_for(callback_id)
        KINDS.find { |_kind, cfg| cfg[:callback_id].call == callback_id }&.first
      end

      def self.build(incident, kind:, private_metadata: nil)
        cfg = KINDS.fetch(kind)
        metadata = private_metadata || Slack::PrivateMetadata.encode(incident_id: incident.id)
        # Launched from a reaction, the caller carries the source message text
        # so the description can start from it.
        initial_description = Slack::PrivateMetadata.parse(metadata).source_message_text

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
