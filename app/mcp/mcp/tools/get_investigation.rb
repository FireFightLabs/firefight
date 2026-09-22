module Mcp
  module Tools
    class GetInvestigation < Base
      tool_name GET_INVESTIGATION
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS
      description "Read one of Halon's investigations: its status, each theory with where it stands and the " \
                  "steps behind it, every step it took, and the finding with each claim and what it rests " \
                  "on. Give the investigation id, or an incident to get its newest run. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          investigation: { type: "string", description: "Investigation UUID" },
          incident: { type: "string", description: "Incident UUID or identifier like INC-42, for its newest investigation" }
        }
      )

      def self.perform(workspace:, args:)
        investigation = find!(workspace, args)
        respond(InvestigationPayloads.full(investigation))
      end

      def self.find!(workspace, args)
        return workspace.investigations.find(args[:investigation].to_s) if args[:investigation].present?
        raise ArgumentError, "Give investigation or incident." if args[:incident].blank?

        incident = IncidentWrite.find!(workspace, args[:incident])
        incident.investigations.order(created_at: :desc).first || raise(ActiveRecord::RecordNotFound)
      end
      private_class_method :find!
    end
  end
end
