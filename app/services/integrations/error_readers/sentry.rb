module Integrations
  module ErrorReaders
    # Sentry's server answers an API error with "There was an HTTP <status> error with your request to the Sentry API." and
    # "API error (<status>): <detail>" (getsentry/sentry-mcp, packages/mcp-core/src/internal/error-handling.ts and
    # api-client/errors.ts), whatever the body was.
    module Sentry
      NOT_FOUND = /HTTP 404 error with your request to the Sentry API|API error \(404\)/

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
