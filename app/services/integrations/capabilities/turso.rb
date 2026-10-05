module Integrations
  module Capabilities
    # Turso answers through its hosted MCP server at mcp.turso.ai. Turso names the server's tools in its agent skill,
    # tursodatabase/turso-mcp skills/turso/SKILL.md, and publishes their parameters only from the server. So the status
    # call names the database with the parameter the connected tool reports, and refuses in words when it reports none
    # Firefight knows. The server offers no logs or metrics over time, only a database's top queries through
    # database_analytics, so status is the one capability Turso answers.
    module Turso
      extend Adapter

      PROVIDER = "Turso".freeze
      PROVIDER_KEY = "turso".freeze
      GET_DATABASE = "get_database".freeze
      SUPPORTS = { STATUS => [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ] }.freeze
      TOOLS = { STATUS => GET_DATABASE }.freeze
      # Its arguments are read off the connected tool, so it stays offered for when they cannot be.
      WRAPPED = [].freeze
      # The names the tool may give the database, in the order they are tried.
      DATABASE = %w[database_name databaseName database name db].freeze

      def self.route(_key, resource, _given, tool: nil, settings: nil)
        name = Answers.named(tool, DATABASE)
        raise Unroutable, "Turso's #{GET_DATABASE} takes the database in a way Firefight does not know yet, so ask it with Turso's own tool." unless name

        Route.new(tool_name: GET_DATABASE, arguments: { name => resource.name })
      end
    end
  end
end
