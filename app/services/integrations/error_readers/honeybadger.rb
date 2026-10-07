module Integrations
  module ErrorReaders
    # Honeybadger's server answers an API error as "<what failed>: HTTP <status>: <message>" (honeybadger-io/honeybadger-mcp-server,
    # internal/hbmcp, with honeybadger-io/api-go errors.go).
    module Honeybadger
      NOT_FOUND = /\bHTTP 404: /

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
