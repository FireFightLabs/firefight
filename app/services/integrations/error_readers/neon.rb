module Integrations
  module ErrorReaders
    # Neon's server answers an API error below 500 with the API's message and again as "[HTTP <status>] <message>", with
    # " (reason: <reason>)" when Neon gave one (neondatabase/mcp-server-neon, mcp/server/errors.ts). A 404 is a not found,
    # except a branch without logs, which Neon answers 404 with reason telemetry_not_enabled, and a key scoped to one project
    # asking outside it (mcp/server/account.ts), which are about access rather than the thing named.
    module Neon
      NOT_FOUND = /\[HTTP 404\]/
      NOT_ABOUT_THE_THING = /reason: telemetry_not_enabled|outside the project|project-scoped/

      def self.not_found?(said) = said.match?(NOT_FOUND) && !said.match?(NOT_ABOUT_THE_THING)
    end
  end
end
