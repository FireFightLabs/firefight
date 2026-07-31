module Slack
  module Modals
    module Roles
      # A view holds 100 blocks. The header and the truncation notice take two,
      # leaving the rest for roles, which is far more than any workspace
      # configures.
      MAX_ROLES = 98

      def self.build(incident, roles)
        shown = roles.first(MAX_ROLES)

        blocks = [ incident_block(incident) ]
        blocks += shown.map { |role| role_block(role, incident) }
        blocks << truncation_notice(roles.size) if roles.size > MAX_ROLES

        {
          type: "modal",
          callback_id: Identifiers::SET_ROLES_MODAL,
          private_metadata: incident.id,
          title: { type: "plain_text", text: "Incident Roles" },
          submit: { type: "plain_text", text: "Save" },
          close: { type: "plain_text", text: "Cancel" },
          blocks: blocks
        }
      end

      def self.incident_block(incident)
        {
          type: "section",
          text: { type: "mrkdwn", text: "*#{incident.identifier}*: #{incident.name || 'Untitled Incident'}" }
        }
      end
      private_class_method :incident_block

      def self.role_block(role, incident)
        holder = incident.role_holder(role)
        element = {
          type: "users_select",
          action_id: Identifiers::ROLE_SELECT,
          placeholder: { type: "plain_text", text: "Select a person" }
        }
        element[:initial_user] = holder.platform_user_id if holder&.platform_user_id

        {
          type: "input",
          block_id: Identifiers.role_block_id(role),
          optional: true,
          element: element,
          label: { type: "plain_text", text: role.name },
          hint: { type: "plain_text", text: hint_for(role) }
        }
      end
      private_class_method :role_block

      # Slack appends a period to hint text that lacks one, which is why stored
      # descriptions are normalized as finished sentences.
      def self.hint_for(role)
        return role.description if role.description.present?
        return "This role cannot be cleared once assigned" if role.unassign_blocked_reason

        "Leave empty to clear this role"
      end
      private_class_method :hint_for

      def self.truncation_notice(total)
        {
          type: "context",
          elements: [
            {
              type: "mrkdwn",
              text: "Showing the first #{MAX_ROLES} of #{total} roles. Disable the ones you no longer use in Settings."
            }
          ]
        }
      end
      private_class_method :truncation_notice
    end
  end
end
