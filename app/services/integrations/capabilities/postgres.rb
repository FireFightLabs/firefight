module Integrations
  module Capabilities
    # A database reached by its connection URL answers how it stands now through the pack's database_status, read from
    # Postgres's own statistics views. Postgres keeps no history of those figures, no log a connection may read without
    # superuser, and no record of deploys, so status is all it answers. The pack only reads, so it changes nothing.
    module Postgres
      extend Adapter

      SUPPORTS = { STATUS => [ ResourceMap::KIND_DATABASE ] }.freeze
      TOOLS = { STATUS => "database_status" }.freeze
      # database_status also answers for a connection whose map sweep has not run yet, so it stays offered as it is.
      WRAPPED = [].freeze

      def self.route(_key, _resource, _given, tool: nil, settings: nil) = Route.new(tool_name: TOOLS[STATUS], arguments: {})
    end
  end
end
