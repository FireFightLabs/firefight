module Mcp
  module Tools
    # The paths Halon may not change in a code host connection's repositories, the list under Code changes on the
    # connection's page. Any file may change while it is empty, since every change arrives as a pull request for review.
    class UpdateProtectedPaths < Base
      tool_name UPDATE_PROTECTED_PATHS
      authorize_as Ability::Action::RESOURCE_INTEGRATIONS, Ability::Action::ACTION_UPDATE
      description "Add or remove paths Halon may not change in the repositories of a code host connection, the list under " \
                  "Code changes on the connection's page. A code change touching one is refused, and a connected coding agent, " \
                  "which pushes its own change, is told to leave them alone. A path is a folder ending in / (.github/), a file " \
                  "(Gemfile.lock) or a pattern: * within a name, ** across folders, ? for one character (infra/prod/**, *.lock). " \
                  "One with no / inside it matches at any depth, one with a / matches from the repository's root. The answer " \
                  "is the whole list after the change. Only a workspace admin may call this. Docs: #{Docs::MCP_SERVER}"
      # It decides what Halon may change, so a chat asks before it applies.
      annotations(**DESTRUCTIVE)
      choice :connection, from: ->(workspace) { workspace.integrations.where(deleted_at: nil).order(:name).select(&:holds_code?) }
      input_schema(
        properties: {
          connection: { type: "string", description: "The code host connection's slug" },
          add: { type: "array", items: { type: "string" }, description: "Paths to add to the list" },
          remove: { type: "array", items: { type: "string" }, description: "Paths to take off the list, as the list writes them" }
        },
        required: [ "connection" ]
      )

      def self.perform(workspace:, args:)
        integration = workspace.integrations.where(deleted_at: nil).find_by(slug: args[:connection].to_s)
        return Mcp::ToolDispatcher.error_response("No connection is called #{args[:connection]}.") unless integration

        added = Integration.listed_paths(args[:add])
        removed = Integration.listed_paths(args[:remove])
        return Mcp::ToolDispatcher.error_response("Give add, remove or both.") if added.empty? && removed.empty?

        missing = removed - integration.protected_paths
        if missing.any?
          listed = integration.protected_paths.presence&.to_sentence || "nothing"
          return Mcp::ToolDispatcher.error_response("#{missing.to_sentence} #{missing.one? ? 'is' : 'are'} not on #{integration.display_name}'s list, which holds #{listed}.")
        end

        refusal = integration.protect_paths!(integration.protected_paths - removed + added)
        return Mcp::ToolDispatcher.error_response(refusal) if refusal

        respond(connection: integration.slug, name: integration.display_name, protected_paths: integration.protected_paths,
                said: integration.protected_paths_words, changed_on: integration.protected_paths_place)
      end
    end
  end
end
