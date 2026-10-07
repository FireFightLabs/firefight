module Integrations
  module ErrorReaders
    # SigNoz's server answers an API error as "SigNoz API error: unexpected status <status>: <detail>"
    # (SigNoz/signoz-mcp-server, internal/handler/tools/errs.go and internal/client/client.go). An older SigNoz without the
    # endpoint answers 404 "route not found" too, which is a missing feature rather than a missing thing.
    module Signoz
      NOT_FOUND = /\ASigNoz API error: unexpected status 404\b/
      NO_SUCH_ROUTE = /route not found/

      def self.not_found?(said) = said.match?(NOT_FOUND) && !said.match?(NO_SUCH_ROUTE)
    end
  end
end
