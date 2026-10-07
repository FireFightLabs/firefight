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

      # The script reading writes, with its options as one JSON value, and a script that makes one request, a GET, written
      # the way a person or the agent writes one. Anything else may change something.
      WRITTEN = /\Aasync \(\) => cloudflare\.request\((?<options>.*)\)\z/m
      ONE_REQUEST = /\A\s*async\s*\(\s*\)\s*=>\s*(?:\{\s*return\s+)?(?:await\s+)?cloudflare\.request\(\s*(?<options>\{(?:[^{}()]|\{[^{}()]*\})*\})\s*\)\s*;?\s*\}?\s*\z/
      GET_METHOD = /["']?\bmethod["']?\s*:\s*(["'`])GET\1/
      ANY_METHOD = /\bmethod\b/
      REQUEST = /cloudflare\.request\(/

      def self.guards?(tool_name) = tool_name == TOOL

      # Whether a call to execute only reads. Firefight's own script is data, so it reads when its request is one reading
      # accepts. A script someone wrote reads only when it is one request whose one method is a GET, since no other text
      # can be shown to read.
      def self.reads?(_tool_name, arguments)
        code = arguments[CODE].to_s
        written = code.match(WRITTEN)
        return written_reads?(written[:options]) if written && json?(written[:options])

        options = code.match(ONE_REQUEST)&.[](:options)
        options.present? && code.scan(REQUEST).one? && options.match?(GET_METHOD) && options.scan(ANY_METHOD).one?
      end

      def self.json?(text)
        JSON.parse(text).is_a?(Hash)
      rescue JSON::ParserError
        false
      end

      def self.written_reads?(text)
        options = JSON.parse(text)
        path = options["path"].to_s
        case options["method"]
        when GET then true
        when POST then path == GRAPHQL ? !options.dig("body", "query").to_s.match?(MUTATION) : path.match?(LOG_QUERY)
        else false
        end
      end

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
