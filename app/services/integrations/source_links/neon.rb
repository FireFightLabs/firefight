module Integrations
  module SourceLinks
    # A Neon result links to the console page of the branch, or the project, the call named. The addresses are the ones
    # Neon's own server writes in neondatabase/mcp-server-neon, mcp/tools/handlers/urls.ts, console.neon.tech/app/projects/<id>
    # and /branches/<id> under it. Every Neon tool names its project and branch by id, so nothing is looked up.
    class Neon
      PROVIDER = MapReaders::Neon::PROVIDER
      NAME = MapReaders::Neon::NAME
      ID = /\A[a-z0-9-]{1,60}\z/

      def initialize(_settings)
      end

      def link(tool_name:, arguments:, text: "")
        asked = arguments.to_h.stringify_keys
        project, branch = asked.values_at("project_id", "branch_id").map { |value| value.to_s[ID] }
        return unless project

        url = branch ? MapReaders::Neon.branch_page(project, branch) : MapReaders::Neon.project_page(project)
        Telemetry::Link.new(provider: NAME, url: url)
      end
    end
  end
end
