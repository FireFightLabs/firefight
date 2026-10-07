module Integrations
  module ErrorReaders
    # Upstash's server answers an API error as "Request failed (<status> <status text>): <body>" (upstash/mcp-server,
    # src/http.ts), so the status says it.
    module Upstash
      NOT_FOUND = /Request failed \(404\b/

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
