module Mcp
  module Tools
    class DeleteAlertSource < Base
      tool_name DELETE_ALERT_SOURCE
      description "Delete an alert source by its endpoint path, only while it holds no alerts. Anything still posting to it starts " \
                  "failing, so disabling it with upsert_alert_source is the reversible move, and the only one once it holds alerts. If " \
                  "the call requires approval, retry the identical call with approval_id once " \
                  "approved. Docs: #{Docs::ALERTS}"
      annotations(**DESTRUCTIVE)
      ends_something
      input_schema(
        properties: {
          slug: { type: "string", description: "Endpoint path of the source to delete" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "slug" ]
      )
      authorize_as Ability::Action::RESOURCE_ALERTS, Ability::Action::ACTION_DELETE

      def self.perform(workspace:, args:)
        source = workspace.alert_sources.find_by!(endpoint_path: args[:slug].to_s)
        source.destroy_guarded!

        respond(slug: args[:slug].to_s, deleted: true)
      rescue OptionGuards::Blocked => e
        refuse(error: e.message)
      end
    end
  end
end
