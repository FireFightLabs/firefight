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

      # graphql_read sends one query to Fly's GraphQL API (superfly/fly-go, schema.graphql), where releases are kept.
      # Firefight's rule refuses a mutation or a subscription. The word is refused anywhere in the document, so a second
      # operation cannot ride along with a query. A query starts only from app(name:) or organization(slug:), so the pack can keep it to
      # the connection's organization, and node, nodes, viewer and the rest are shaped wrong. Secrets, tokens, keys,
      # passwords, credentials and an app's or release's config and environment (configDefinition holds fly.toml's env)
      # can be read under an alias, so a query naming any of them is read as names only.
      GRAPHQL = "graphql_read".freeze
      QUERY = "query".freeze
      VARIABLES = "variables".freeze
      CHANGE = /\b(mutation|subscription)\b/i
      SECRET_FIELDS = /\b(\w*[Ss]ecrets?\w*|\w*[Tt]okens?\w*|\w*[Pp]assword\w*|\w*[Cc]redentials?\w*|\w*[Kk]eys?|config\w*|\w*Config\w*|env\w*|\w*Env\w*)\b/
      QUERY_LIMIT = 10_000
      ROOTS = { "app" => "name", "organization" => "slug" }.freeze
      TYPENAME = "__typename".freeze
      FRAGMENT = "fragment".freeze
      NOT_A_CHANGE = "Fly.io's GraphQL read only runs a query. A mutation or a subscription changes or holds something, so it is " \
                     "never sent. A change belongs in a fix.".freeze
      ROOTS_WORDS = "A query starts from app(name: \"<app>\") or organization(slug: \"<organization>\"), such as " \
                    "{ app(name: \"web\") { releasesUnprocessed(first: 20) { nodes { version status createdAt } } } }.".freeze
      # One part of a query: a name, a variable, a string, or one punctuation mark. Comments are dropped.
      TOKEN = /"(?:[^"\\]|\\.)*"|#[^\n]*|\$?[A-Za-z_]\w*|\.\.\.|[^\s,]/
      # What a query's top level asks for: app or organization, by the name or slug it names.
      Root = Data.define(:field, :value)

      def self.guards?(tool_name) = [ ApiReads::TOOL, GRAPHQL ].include?(tool_name)

      def self.reads?(tool_name, arguments)
        return super unless tool_name == GRAPHQL

        reading(tool_name, arguments)
        true
      rescue Refused, PolicyRefusal
        false
      end

      # A path outside the Machines API is shaped wrong, which the agent can fix, rather than refused by a rule.
      def self.reading(tool_name, arguments)
        return graphql_reading(arguments) if tool_name == GRAPHQL
        raise Refused, OUTSIDE unless ApiReads.path!(arguments["path"]).match?(PATH)

        super
      end

      def self.graphql_reading(arguments)
        text = arguments[QUERY].to_s.strip
        raise Refused, "query must be the GraphQL query to run. #{ROOTS_WORDS}" if text.empty?
        raise Refused, "query is too long, so read less at once." if text.length > QUERY_LIMIT
        raise PolicyRefusal, NOT_A_CHANGE if text.match?(CHANGE)

        variables = arguments[VARIABLES]
        raise Refused, "variables must be an object of the query's variables by name." unless variables.nil? || variables.is_a?(Hash)

        roots(text, variables.to_h)
        arguments.merge(QUERY => text, VARIABLES => variables.to_h)
      end

      # Every field the query asks for at its top level, each with the app name or organization slug it gives, from a
      # literal or a variable. Refused when one is anything else or names neither. A fragment's own fields are not the
      # top level, since a fragment is only ever spread inside a field the query starts from.
      def self.roots(text, variables)
        tokens = text.scan(TOKEN).reject { |token| token.start_with?("#") }
        found = []
        depth = parens = index = 0
        fragment = false
        while index < tokens.size
          token = tokens[index]
          case token
          when "(" then parens += 1
          when ")" then parens -= 1
          when "{" then depth += 1 if parens.zero?
          when "}"
            depth -= 1 if parens.zero?
            fragment = false if depth.zero?
          else
            fragment = true if depth.zero? && token == FRAGMENT
            if depth == 1 && parens.zero? && !fragment
              index += 2 if tokens[index + 1] == ":"
              found << root(tokens, index, variables)
            end
          end
          index += 1
        end
        found.compact.tap { |kept| raise Refused, ROOTS_WORDS if kept.empty? }
      end

      def self.root(tokens, index, variables)
        field = tokens[index].to_s
        return if field == TYPENAME
        raise Refused, "#{field} is not where Fly.io's GraphQL read starts. #{ROOTS_WORDS}" unless ROOTS.key?(field)

        wanted = ROOTS[field]
        given = tokens[index + 1] == "(" && tokens[index + 2] == wanted && tokens[index + 3] == ":" ? tokens[index + 4].to_s : ""
        value = given.start_with?("$") ? variables[given.delete_prefix("$")].to_s : given.delete_prefix("\"").delete_suffix("\"")
        raise Refused, "#{field} is read by #{wanted} alone, such as #{field}(#{wanted}: \"<#{wanted}>\")." if value.blank? || tokens[index + 5] != ")"

        Root.new(field: field, value: value)
      end
      private_class_method :root

      # Whether the query reads a field that answers secrets, so its whole answer is read as names.
      def self.graphql_secret?(text) = text.to_s.gsub(/\$\w+/, "").match?(SECRET_FIELDS)

      def self.refusal(path, query)
        return OUTSIDE unless path.match?(PATH)
        return "show_secrets asks Fly.io for secrets' values, so a read never sends it. Read them without it for their names." if query.key?(SHOW_SECRETS)

        super
      end
    end
  end
end
