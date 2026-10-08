module Mcp
  module Tools
    # Stops a watch Halon keeps for whoever this key belongs to.
    class StopWatch < Base
      tool_name STOP_WATCH
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
      description "Stop a watch Halon keeps for you, by the id list_watches gives. It says it stopped where it reports. " \
                  "Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: { watch: { type: "string", description: "Watch UUID, from list_watches" } },
        required: [ "watch" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        watch = Chat::Watch.where(workspace_id: workspace.id, asker: principal).find(args[:watch].to_s)
        blocked = Conversation::Watches.stop!(watch, by: principal)
        return Mcp::ToolDispatcher.error_response(blocked) if blocked

        respond(Conversation::Watches::Shown.summary(watch.reload))
      end
    end
  end
end
