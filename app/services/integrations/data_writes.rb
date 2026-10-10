module Integrations
  # Tools that change rows with a SQL statement, which a provider names in its data_writes part. Before Halon runs one
  # Firefight counts the rows the statement touches and shows a few, keeps a copy of them, and checks afterwards
  # (Chat::DataRepairs). Every read it makes for that goes through the provider's own tool, so nothing here knows a
  # provider's API.
  module DataWrites
    # One tool that writes. sql is the argument holding the statement, or the list of them for a tool that runs several
    # in one transaction (many), read_tool the tool that runs a read on the same database with the same other arguments
    # (the tool itself when it runs reads too), read_sql the argument that tool takes its statement in, and dropped the
    # arguments only a write takes, left out of a read.
    Tool = Data.define(:name, :sql, :read_tool, :read_sql, :dropped, :many) do
      def initialize(name:, sql:, read_tool: nil, read_sql: nil, dropped: [], many: false)
        super(name: name.to_s, sql: sql.to_s, read_tool: (read_tool || name).to_s, read_sql: (read_sql || sql).to_s, dropped: dropped.map(&:to_s), many: many)
      end

      # The statements a call runs, as text.
      def statements(given)
        value = given[sql]
        many ? Array(value).map(&:to_s) : [ value.to_s ]
      end
    end

    # A provider's tools that write rows.
    class Definition
      def initialize(*tools)
        @tools = tools.index_by(&:name).freeze
      end

      def tool(name) = @tools[name.to_s]

      def names = @tools.keys
    end

    # The rows a statement touches are counted under this name, so a count can be found in any provider's answer, as
    # JSON, a grid or plain text.
    COUNT_COLUMN = "halon_rows".freeze
    # The most rows one write may touch, since every one is copied before it runs. A larger repair goes in batches.
    COPY_LIMIT = 1_000
    COUNT_IN_ANSWER = /#{COUNT_COLUMN}\W{0,40}?(\d+)/

    # The tool's write definition when its provider declares one, or nil.
    def self.for(tool)
      return if tool.nil? || tool.read_only?

      Provider.for(tool.integration.provider).data_writes&.tool(tool.name)
    end

    def self.write_tool?(tool) = self.for(tool).present?

    # The switched on tool that reads for a write, the write itself when it reads too, or nil.
    def self.read_tool(tool, definition)
      return tool if definition.read_tool == tool.name

      Integration::Tool.in_workspace(tool.integration.workspace).find { |each| each.integration_id == tool.integration_id && each.name == definition.read_tool }
    end

    # The count a counting read answered, or nil when the answer holds none.
    def self.count_in(text)
      found = text.to_s[COUNT_IN_ANSWER, 1]
      found&.to_i
    end
  end
end
