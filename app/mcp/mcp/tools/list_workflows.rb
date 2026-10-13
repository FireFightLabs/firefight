module Mcp
  module Tools
    # The workspace's workflows, the same list Halon reads in a chat.
    class ListWorkflows < Base
      tool_name LIST_WORKFLOWS
      authorize_as Ability::Action::RESOURCE_WORKFLOWS
      behind_flag FeatureFlags::WORKFLOWS
      description "List the workspace's workflows: each one's name and other names, what starts it (by hand, on a schedule or once at a " \
                  "time), whether it is live, when it runs next, how its last run went, its steps and the inputs a run asks. " \
                  "Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      own_words
      input_schema(properties: {})

      def self.perform(workspace:, args:)
        respond(workflows: Workflow::Listing.for(workspace))
      end
    end
  end
end
