module Integrations
  module ReadGuards
    # execute runs JavaScript, and no check of a script's text can prove it only reads. So while investigating it takes
    # one request as data, a GET or a query to the GraphQL Analytics API, and Firefight writes the script itself with
    # each value as a JSON literal, the way the map's reader does. The model's words never become code.
    module Cloudflare
      TOOL = "execute".freeze
      CODE = "code".freeze
      ACCOUNT = "account_id".freeze
      GET = "GET".freeze
      POST = "POST".freeze
      GRAPHQL = "/graphql".freeze
      PATH = %r{\A(/[A-Za-z0-9_-]+)+\z}
      MUTATION = /\bmutation\b/i
      # Workers Observability's log query only reads, though Cloudflare takes it as a POST.
      LOG_QUERY = %r{\A/accounts/[A-Za-z0-9]+/workers/observability/telemetry/query\z}

      SCHEMA = {
        "type" => "object",
        "properties" => {
          "method" => { "type" => "string", "enum" => [ GET, POST ], "description" => "GET, or POST only for #{GRAPHQL} or a Workers log query" },
          "path" => { "type" => "string", "description" => "The API path, such as /zones or /zones/<zone id>/dns_records, or #{GRAPHQL}" },
          "query" => { "type" => "object", "description" => "Query parameters for a GET, such as {\"per_page\": 50} (optional)" },
          "graphql" => { "type" => "string", "description" => "The GraphQL Analytics query, for POST #{GRAPHQL} (optional)" },
          "variables" => { "type" => "object", "description" => "Variables for the GraphQL query (optional)" },
          "body" => { "type" => "object", "description" => "The query, for POST to /accounts/<account id>/workers/observability/telemetry/query (optional)" },
          ACCOUNT => { "type" => "string", "description" => "The account to read, when the connection belongs to a person (optional)" }
        },
        "required" => %w[method path]
      }.freeze
      DESCRIPTION = "While investigating, #{TOOL} reads one thing per call: a GET to a Cloudflare API path with its query, " \
                    "a GraphQL Analytics query as POST #{GRAPHQL}, or a Workers log query as POST to " \
                    "/accounts/<account id>/workers/observability/telemetry/query. A change belongs in the fix.".freeze

      def self.guards?(tool_name) = tool_name == TOOL

      def self.schema = SCHEMA

      def self.reading(_tool_name, arguments)
        method = arguments["method"].to_s.upcase
        path = arguments["path"].to_s
        raise Refused, "path must be a Cloudflare API path, such as /zones." unless path.match?(PATH)

        options = case method
        when GET then get(path, arguments["query"])
        when POST then path.match?(LOG_QUERY) ? log_query(path, arguments["body"]) : graphql(path, arguments["graphql"], arguments["variables"])
        else raise Refused, DESCRIPTION
        end
        arguments_for(options, arguments[ACCOUNT])
      end

      # execute's own arguments for one request Firefight wrote, each value a JSON literal so no words become code.
      def self.arguments_for(options, account_id)
        { CODE => "async () => cloudflare.request(#{JSON.generate(options)})", ACCOUNT => account_id.presence }.compact
      end

      def self.get(path, query)
        raise Refused, "query must be an object." unless query.nil? || query.is_a?(Hash)

        { "method" => GET, "path" => path, "query" => query }.compact
      end

      def self.log_query(path, body)
        raise Refused, "body must be the log query." unless body.is_a?(Hash)

        { "method" => POST, "path" => path, "body" => body }
      end

      def self.graphql(path, text, variables)
        raise Refused, DESCRIPTION unless path == GRAPHQL
        raise Refused, "graphql must be the query to run." if text.to_s.strip.empty?
        raise Refused, "A GraphQL mutation changes something. #{DESCRIPTION}" if text.match?(MUTATION)
        raise Refused, "variables must be an object." unless variables.nil? || variables.is_a?(Hash)

        { "method" => POST, "path" => GRAPHQL, "body" => { "query" => text, "variables" => variables }.compact }
      end
    end
  end
end
