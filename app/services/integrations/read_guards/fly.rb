module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Fly.io's Machines API (docs.fly.io/api/machines/openapi.json, paths under /v1), so
    # what the guard settles is which GETs answer secrets or hold the call open. show_secrets asks Fly for secrets' values
    # (spec, Secrets_list and Secret_get), so it is never sent, and secrets and secret keys read as their names. A Managed
    # Postgres user's credentials are its password (spec, GET /v1/postgres/{postgres_cluster_id}/users/{username}/credentials).
    # A machine's lease answers the nonce that lets whoever holds it change the machine (spec, Machines_show_lease). A
    # machine's wait holds the call open until the machine reaches a state, up to a minute (spec, Machines_wait), which is
    # a read of the machine itself. The current token's details read as names.
    module Fly
      extend PathReads

      REFUSED = {
        %r{\A/v1/postgres/[^/]+/users/[^/]+/credentials\z} =>
          "A Managed Postgres user's credentials are its password, so a read never fetches them. The cluster's users are listed at /v1/postgres/<cluster id>/users.",
        %r{\A/v1/apps/[^/]+/machines/[^/]+/wait\z} =>
          "A machine's wait holds the call open until the machine changes state. Read the machine itself at /v1/apps/<app>/machines/<machine id> for its state."
      }.freeze
      SECRET_PATHS = %r{/(secrets|secretkeys)(/|\z)|/machines/[^/]+/lease\z|\A/v1/tokens(/|\z)}
      SHOW_SECRETS = "show_secrets".freeze
      PATH = %r{\A/v1/}

      OUTSIDE = "Fly.io's Machines API paths start with /v1, such as /v1/apps/<app>/machines.".freeze

      # A path outside the Machines API is shaped wrong, which the agent can fix, rather than refused by a rule.
      def self.reading(tool_name, arguments)
        raise Refused, OUTSIDE unless ApiReads.path!(arguments["path"]).match?(PATH)

        super
      end

      def self.refusal(path, query)
        return OUTSIDE unless path.match?(PATH)
        return "show_secrets asks Fly.io for secrets' values, so a read never sends it. Read them without it for their names." if query.key?(SHOW_SECRETS)

        super
      end
    end
  end
end
