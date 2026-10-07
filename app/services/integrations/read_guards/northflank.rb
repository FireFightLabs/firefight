module Integrations
  module ReadGuards
    # api_request reads with GET and writes with anything else, so the method settles it.
    module Northflank
      TOOL = "api_request".freeze
      READ = "GET".freeze

      def self.guards?(tool_name) = tool_name == TOOL

      # The tool's own schema serves, since its method already says whether it reads.
      def self.schema = nil

      def self.reads?(_tool_name, arguments) = arguments["method"].to_s.upcase == READ

      def self.reading(_tool_name, arguments)
        return arguments if arguments["method"].to_s.upcase == READ

        raise Refused, "While investigating, #{TOOL} only reads, so its method must be #{READ}. A change belongs in the fix."
      end
    end
  end
end
