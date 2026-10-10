module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Vercel's REST API (openapi.vercel.sh), so what the guard settles is which GETs
    # answer secrets. decrypt=true asks Vercel for an environment variable's value in the clear (spec, filterProjectEnvs,
    # decrypt), so it is never sent. Environment variables, a project's or the team's shared ones, read as their names
    # (spec, filterProjectEnvs, getProjectEnv, which answers one variable decrypted, and listSharedEnvVariable). Log
    # drains and drains carry the headers they send, which hold their receivers' keys (spec, getLogDrains and getDrains,
    # headers), and tokens, an Edge Config's or the account's, are credentials (spec, getEdgeConfigTokens and listAuthTokens),
    # so all of these read as names too.
    module Vercel
      extend PathReads

      REFUSED = {}.freeze
      SECRET_PATHS = %r{/env(/|\z)|/(log-)?drains(/|\z)|/tokens?(/|\z)}
      DECRYPT = "decrypt".freeze

      def self.refusal(path, query)
        if query.key?(DECRYPT) && query[DECRYPT].to_s != "false"
          return "decrypt asks Vercel for environment variables' values in the clear, so a read never sends it. Read them without it for their names."
        end

        super
      end
    end
  end
end
