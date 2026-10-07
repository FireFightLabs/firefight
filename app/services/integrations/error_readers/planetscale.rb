module Integrations
  module ErrorReaders
    # PlanetScale's tools generated from its API answer an error with the API's body, which for a missing database or
    # branch is {"code":"not_found","message":"Not Found"}, and its own tools end the error with "(status: 404)"
    # (planetscale/mcp-server, src/lib/planetscale-api.ts). Both were seen from the hosted server.
    module Planetscale
      NOT_FOUND = /"code"\s*:\s*"not_found"|\(status: 404\)/

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
