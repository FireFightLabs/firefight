module Integrations
  module Capabilities
    # A database reached by its connection URL answers how it stands now through the pack's database_status, and what went
    # wrong through database_errors: rollbacks, deadlocks and conflicts from pg_stat_database, and the queries that cost
    # the most from pg_stat_statements where it is installed. Both are counted since the statistics were last reset, which
    # the answer names, so a time range asked is not sent. Postgres keeps no log a connection may read without superuser and no record of
    # deploys, and the pack only reads, so it changes nothing.
    module Postgres
      extend Adapter

      SUPPORTS = { STATUS => [ ResourceMap::KIND_DATABASE ], ERRORS => [ ResourceMap::KIND_DATABASE ] }.freeze
      TOOLS = { STATUS => "database_status", ERRORS => "database_errors" }.freeze
      # Both also answer for a connection whose map sweep has not run yet, so they stay offered as they are.
      WRAPPED = [].freeze
      OWN_PHRASES = { ERRORS => "read its rollbacks, deadlocks and costliest queries" }.freeze

      def self.phrase(key) = OWN_PHRASES.fetch(key) { super }

      def self.route(key, _resource, given, tool: nil, settings: nil)
        return Route.new(tool_name: TOOLS[STATUS], arguments: {}) if key == STATUS

        Route.new(tool_name: TOOLS[ERRORS], arguments: given.slice("text", "limit").compact_blank)
      end
    end
  end
end
