module Integrations
  module ErrorReaders
    # PostHog's server answers an API error with "Status Code: <status> (<status text>)" on its own line
    # (PostHog/posthog, services/mcp/src/lib/errors.ts), and a missing experiment as "Experiment <id> not found in this
    # project" (services/mcp/src/api/client.ts).
    module Posthog
      NOT_FOUND = /^Status Code: 404\b|\bExperiment \d+ not found in this project\b/

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
