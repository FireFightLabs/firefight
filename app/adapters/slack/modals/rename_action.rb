module Slack
  module Modals
    # Renames an action or a follow-up, holding the title it has now.
    module RenameAction
      BLOCK = "title_block".freeze
      INPUT = "title_input".freeze

      def self.build(action)
        {
          type: "modal",
          callback_id: Identifiers::RENAME_ACTION_MODAL,
          private_metadata: ModalState.encode(incident_id: action.incident_id, action_item_id: action.id),
          title: { type: "plain_text", text: "Rename item" },
          submit: { type: "plain_text", text: "Rename" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            {
              type: "input",
              block_id: BLOCK,
              element: { type: "plain_text_input", action_id: INPUT, multiline: true, max_length: IncidentAction::TITLE_LIMIT, initial_value: action.description },
              label: { type: "plain_text", text: "Title" },
              hint: { type: "plain_text", text: hint(action) }
            }
          ]
        }
      end

      def self.hint(action)
        return "Say what needs doing, the way it reads in the incident." if action.external_key.blank?

        "#{action.external_key} takes the new title too."
      end

      def self.title(values) = values.dig(BLOCK, INPUT, "value")
    end
  end
end
