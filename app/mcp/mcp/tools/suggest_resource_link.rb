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
        visible = ResourceMap::Resource.visible_to(principal, workspace)
        from = one(workspace, visible, args[:from])
        return from if from.is_a?(::MCP::Tool::Response)

        to = one(workspace, visible, args[:to])
        return to if to.is_a?(::MCP::Tool::Response)

        link = ResourceMap::Link.suggest!(from: from, to: to, relation: args[:relation].to_s, note: args[:evidence].to_s.strip)
        return respond(error: link) if link.is_a?(String)

        respond(suggested: link.sentence, note: "Shown on the map as a suggestion until a person confirms it.")
      end

      def self.one(workspace, visible, reference)
        found = visible.referenced(workspace, reference).present.includes(integration_environment: :integration).to_a
        return respond(error: "Nothing called #{reference} is on the map. get_resource_map shows what is.") if found.empty?
        return found.first if found.one?

        named = found.map do |each|
          "#{each.kind} #{each.scoped_name} (map id #{each.id}, on #{each.integration_environment&.integration&.display_name || each.provider}, its provider's id #{each.external_id})"
        end
        respond(error: "More than one resource is called #{reference}: #{named.join(', ')}. Name one by its map id.")
      end
    end
  end
end
