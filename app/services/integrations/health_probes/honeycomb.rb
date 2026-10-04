module Integrations
  module HealthProbes
    # Reads Honeycomb's workspace through get_workspace_context, which only works with a sign in or key Honeycomb accepts,
    # and checks that the environment the connection was set up for is one of the team's, since every query names it.
    # The tool, and that it lists the team's environments with their slugs, are from Honeycomb's MCP documentation
    # (docs.honeycomb.io/integrations/mcp/tools). It learns nothing to keep.
    class Honeycomb < RemoteReader
      WORKSPACE = "get_workspace_context".freeze

      def check!
        result = call(WORKSPACE)
        return if result.nil?

        text = Capabilities::Answers.text(result)
        refused!(WORKSPACE, result)

        slug = Capabilities::Honeycomb.environment(settings)
        return if slug.nil? || text.match?(/(?<![\w-])#{Regexp.escape(slug)}(?![\w-])/)

        raise Refused, "Honeycomb does not list an environment called #{slug} for this team. Connect again with the slug of one it does."
      end
    end
  end
end
