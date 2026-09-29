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
          from: { type: "string", description: "The resource that depends, by name or provider id, such as web" },
          to: { type: "string", description: "The resource it depends on, such as firefight-prod/main" },
          relation: { type: "string", enum: ResourceMap::RELATIONS, description: "How from depends on to, read as from uses to, from runs builds of to, and so on" },
          evidence: { type: "string", description: "What you read that shows the link, in one or two sentences" }
        },
        required: [ "from", "to", "relation", "evidence" ]
      )

      def self.perform(workspace:, args:)
        from = one(workspace, args[:from])
        return from if from.is_a?(::MCP::Tool::Response)

        to = one(workspace, args[:to])
        return to if to.is_a?(::MCP::Tool::Response)

        link = ResourceMap::Link.suggest!(from: from, to: to, relation: args[:relation].to_s, note: args[:evidence].to_s.strip)
        return respond(error: link) if link.is_a?(String)

        respond(suggested: link.sentence, note: "Shown on the map as a suggestion until a person confirms it.")
      end

      def self.one(workspace, reference)
        found = ResourceMap::Resource.named(workspace, reference).present.to_a
        return respond(error: "Nothing called #{reference} is on the map. get_resource_map shows what is.") if found.empty?
        return found.first if found.one?

        respond(error: "More than one resource is called #{reference}: #{found.map { |each| "#{each.external_id} (#{each.provider} #{each.kind})" }.join(', ')}. Name one by its id.")
      end
    end
  end
end
