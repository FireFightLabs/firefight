module Mcp
  module Tools
    # The outside systems the workspace's apps use that no connection reaches (Upstream::BlindSpots), with where each was
    # seen and how to connect it, so a question that needs one is answered by naming it rather than by guessing.
    class BlindSpots < Base
      tool_name BLIND_SPOTS
      authorize_as Ability::Action::RESOURCE_MAP
      description "The outside systems this workspace's apps use that Firefight has no connection for, such as a sign-in, " \
                  "payment or email provider, each with where it was seen (a service's setting named for it or pointing at " \
                  "its host, or the catalog) and how to connect it or read its status. Call it when a question may need a " \
                  "system you hold no tool for, such as failed logins when sign-in runs through an outside provider, and say " \
                  "which system it is rather than guessing what it did. Docs: #{Docs::WHAT_CHANGED}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          category: { type: "string", enum: Upstream.all.map(&:category).uniq.sort, description: "Only systems of this kind (optional)" }
        },
        required: []
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        spots = Upstream::BlindSpots.new(workspace, principal, category: args[:category]).spots
        return respond(blind_spots: [], note: Upstream::BlindSpots::NONE) if spots.empty?

        respond(blind_spots: spots.map(&:to_h))
      end
    end
  end
end
