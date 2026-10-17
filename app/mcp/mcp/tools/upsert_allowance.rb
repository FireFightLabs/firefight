module Mcp
  module Tools
    class UpsertAllowance < Base
      tool_name FirefightTools::UPSERT_ALLOWANCE
      description "Add or change an entry of what Halon may do without asking in a person's chat, so a risky change it covers " \
                  "runs without the person's yes and is said in the chat after, in the activity log with the entry named. Name " \
                  "a capability or one connection's tool, not both. An entry grants nothing, and an approval rule still holds " \
                  "what it covers. A change to access or a secret, a statement that writes rows, a general tool and a tool on a " \
                  "remote server are refused. Pass id to update, and only the keys given change, so enabled alone turns an entry " \
                  "on or off. Omit id to add. Docs: #{Docs::WITHOUT_ASKING}"
      annotations(**WRITE)
      input_schema(
        properties: {
          id: { type: "string", description: "Entry id to update, omit to add" },
          capability: { type: [ "string", "null" ], enum: [ *Ability::Allowance::CAPABILITIES, nil ], description: "A capability Halon may use without asking" },
          action_key: { type: [ "string", "null" ], description: "Instead of a capability, one connection's tool by its key, as list_abilities names it" },
          integration: { type: [ "string", "null" ], description: "Keep a capability to one connection, by its slug. null for any" },
          environment: { type: [ "string", "null" ], description: "Keep the entry to one environment, by its id or name. null for every one" },
          enabled: { type: "boolean", description: "Switch the entry off without deleting it" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      # It authorizes as permissions either way, which only a person's say lets through.
      def self.asks_a_person? = true

      def self.token_refusal(_workspace, _args) = Ability::Allowance.change_blocked_reason(AbilityGateway::SOURCE_MCP)

      def self.authorization(workspace, args)
        action = existing(workspace, args) ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE
        [ Ability::Action::RESOURCE_PERMISSIONS, action ]
      end

      def self.perform_with_principal(workspace:, principal:, args:)
        found = existing(workspace, args)
        raise ActiveRecord::RecordNotFound if args[:id].present? && found.nil?

        changes = Ability::Allowance.changes_from(workspace, args.except(:id, :approval_id))
        allowance = found || workspace.allowances.new(created_by: (principal if principal.is_a?(WorkspaceMembership)))
        allowance.update!(changes)
        respond(allowance.payload)
      rescue ActiveRecord::RecordInvalid => e
        Mcp::ToolDispatcher.error_response(e.record.errors.full_messages.join(" "))
      end

      def self.existing(workspace, args)
        return nil if args[:id].blank?

        workspace.allowances.find_by(id: args[:id].to_s)
      end
    end
  end
end
