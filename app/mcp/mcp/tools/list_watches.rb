module Mcp
  module Tools
    # The watches Halon keeps for whoever this key belongs to, started from ask_halon or anywhere else they asked.
    class ListWatches < Base
      tool_name LIST_WATCHES
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS
      description "List the watches Halon keeps for you: what each follows, its time limit and why, each step as it " \
                  "stands, everything it said, and how it ended. Ask Halon (ask_halon) to be told when something finishes " \
                  "to start one. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          active: { type: "boolean", description: "Only the ones still going (optional)" }
        }
      )

      LIMIT = 50

      def self.perform_with_principal(workspace:, principal:, args:)
        watches = Chat::Watch.where(workspace_id: workspace.id, asker: principal).includes(:asker, :steps, :updates).order(created_at: :desc)
        watches = watches.active if ActiveModel::Type::Boolean.new.cast(args[:active])
        respond(watches: watches.limit(LIMIT).map { |watch| Chat::Watch::Shown.summary(watch) })
      end
    end
  end
end
