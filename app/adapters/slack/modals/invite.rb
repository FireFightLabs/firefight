module Slack
  module Modals
    module Invite
      def self.build(incident, selected_user_ids: [], private_metadata: nil)
        element = {
          type: "multi_users_select",
          action_id: "invite_users_select",
          placeholder: { type: "plain_text", text: "Select people to invite" }
        }
        element[:initial_users] = selected_user_ids if selected_user_ids.present?

        {
          type: "modal",
          callback_id: Identifiers::INVITE_RESPONDERS_MODAL,
          private_metadata: private_metadata || incident.id,
          title: { type: "plain_text", text: "Invite responders" },
          submit: { type: "plain_text", text: "Invite" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: [
            { type: "section", text: { type: "mrkdwn", text: "*#{incident.identifier}: #{incident.name || 'Untitled Incident'}*" } },
            {
              type: "input",
              block_id: "invite_users_block",
              element: element,
              label: { type: "plain_text", text: "Who should join this channel?" }
            }
          ]
        }
      end
    end
  end
end
