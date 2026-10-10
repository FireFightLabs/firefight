module Integrations
  module ReadGuards
    # Railway's public API is GraphQL only (docs.railway.com/integrations/api), so api_read sends one GraphQL query with
    # its variables. A mutation or a subscription is refused by Firefight's rule, and the word is refused anywhere in the
    # document, so a second operation can never ride along with a query. variables and variablesForServiceDeployment
    # answer every variable's value (schema, Query.variables), an environment's config holds its services' variables, and
    # tokens are credentials. A field can be read under an alias, so a query naming any of these is read as names only.
    module Railway
      TOOL = ApiReads::TOOL
      QUERY = "query".freeze
      VARIABLES = "variables".freeze
      CHANGE = /\b(mutation|subscription)\b/i
      SECRET_FIELDS = /\b(variables\w*|config|rawConfig|\w*[Tt]okens?|\w*[Ss]ecrets?|\w*[Pp]assword\w*|\w*[Cc]redentials?|connectionString)\s*[({]?/
      QUERY_LIMIT = 10_000
      NOT_A_CHANGE = "Railway's general read only runs a GraphQL query. A mutation or a subscription changes or holds something, " \
                     "so it is never sent. A change belongs in a fix.".freeze

      def self.guards?(tool_name) = tool_name == TOOL

      # The tool's own schema serves, since it can only ever read.
      def self.schema = nil

      def self.reads?(_tool_name, arguments)
        reading(TOOL, arguments)
        true
      rescue Refused, PolicyRefusal
        false
      end

      # The call with its query and variables as sent, or PolicyRefusal for a change, or Refused for a call shaped wrong.
      def self.reading(_tool_name, arguments)
        text = arguments[QUERY].to_s.strip
        raise Refused, "query must be the GraphQL query to run, such as { project(id: \"<id>\") { name } }." if text.empty?
        raise Refused, "query is too long, so read less at once." if text.length > QUERY_LIMIT
        raise PolicyRefusal, NOT_A_CHANGE if text.match?(CHANGE)

        variables = arguments[VARIABLES]
        raise Refused, "variables must be an object of the query's variables by name." unless variables.nil? || variables.is_a?(Hash)

        arguments.merge(QUERY => text, VARIABLES => variables.to_h)
      end

      # Whether the query reads a field that answers secrets, so its whole answer is read as names.
      def self.secret?(text) = text.to_s.gsub(/\$\w+/, "").match?(SECRET_FIELDS)
    end
  end
end
