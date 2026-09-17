module Mcp
  module Tools
    class SearchSimilar < Base
      tool_name SEARCH_SIMILAR
      authorize_as Ability::Action::RESOURCE_INCIDENTS
      description "Find past incidents, findings and postmortems that read like the situation you " \
                  "describe, by meaning rather than by words. Say what is happening in a sentence " \
                  "or two. Results say whether an incident is still open, so an unfinished one is " \
                  "not an answer. Docs: #{Docs::INCIDENTS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          query: { type: "string", description: "What is happening, in a sentence or two" },
          limit: { type: "integer", description: "Max results, up to 50 (default 25)" }
        },
        required: [ "query" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        query = args[:query].to_s.squish
        return Mcp::ToolDispatcher.error_response("Say what is happening first.") if query.blank?

        matches = SearchEmbedding.similar_to(
          query, workspace: workspace, limit: limit_for(args), types: readable_types(workspace, principal)
        )
        respond(matches: matches.map { |match| summary(match) })
      end

      # A finding is an investigation's answer, and this call was authorized to read incidents.
      def self.readable_types(workspace, principal)
        types = [ Incident.name, Postmortem.name ]
        resolved = Ability::Resolver.resolve(principal, workspace)
        findings_key = Ability::Action.system_key(
          Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_READ
        )
        types << Investigation::Finding.name if resolved.action_keys.include?(findings_key)
        types
      end

      def self.limit_for(args)
        limit = args[:limit].to_i
        limit = DEFAULT_LIMIT unless limit.positive?
        [ limit, MAX_LIMIT ].min
      end

      def self.summary(match)
        { type: match.kind, similarity: match.similarity.round(3) }.merge(match.facts)
      end
    end
  end
end
