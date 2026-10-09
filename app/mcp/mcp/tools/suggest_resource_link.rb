module Mcp
  module Tools
    # How two resources depend on each other, as the agent read it from evidence. It is shown dashed on the map and is
    # not a fact until a person confirms it, so it never changes what the sweeps report.
    class SuggestResourceLink < Base
      tool_name SUGGEST_RESOURCE_LINK
      authorize_as Ability::Action::RESOURCE_CATALOG, Ability::Action::ACTION_UPDATE
      description "Suggest a link between two resources on the map that no provider declares, such as a service that " \
                  "uses a database, from evidence you read (a connection host in its logs, requests between them). It " \
                  "shows on the map as a suggestion until a person confirms or dismisses it. Say what the evidence " \
                  "was. Name each resource as get_resource_map shows it. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          from: { type: "string", description: "The resource that depends, by its name, its provider's id or its id on the map, such as web" },
          to: { type: "string", description: "The resource it depends on, the same way, such as firefight-prod/main" },
          relation: { type: "string", enum: ResourceMap::RELATIONS, description: "How from relates to to, read as from uses to, from runs builds of to, from is managed in to, and so on" },
          evidence: { type: "string", description: "What you read that shows the link, in one or two sentences" }
        },
        required: [ "from", "to", "relation", "evidence" ]
      )

      # Both ends are found among what the principal reads on the map, so one outside it answers as not on the map.
      def self.perform_with_principal(workspace:, principal:, args:)
        from = ResourceMap::Resource.locate(workspace, principal, args[:from])
        return refuse(error: from) if from.is_a?(String)

        to = ResourceMap::Resource.locate(workspace, principal, args[:to])
        return refuse(error: to) if to.is_a?(String)

        link = ResourceMap::Link.suggest!(from: from, to: to, relation: args[:relation].to_s, note: args[:evidence].to_s.strip)
        return refuse(error: link) if link.is_a?(String)

        respond(suggested: link.sentence, note: "Shown on the map as a suggestion until a person confirms it.")
      end
    end
  end
end
