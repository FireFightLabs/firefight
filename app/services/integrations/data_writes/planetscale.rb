module Integrations
  module DataWrites
    # PlanetScale's server writes with execute_write_query and reads the same branch with execute_read_query, both taking
    # the statement as query. confirm_destructive is a write's alone.
    Planetscale = Definition.new(
      Tool.new(name: "execute_write_query", sql: "query", read_tool: "execute_read_query", dropped: %w[confirm_destructive])
    )
  end
end
