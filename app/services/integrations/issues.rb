module Integrations
  # An issue a provider's tool opened or closed, so the platform keeps the incident work it tracks in step with an issue
  # tracker without knowing which tracker it is. A provider says so through its definition's issue_tracker, a
  # RemoteReader answering report(tool_name:, arguments:, result:) with a Report, or nil when the call did neither, whose
  # OPENS names the tools that can open one.
  module Issues
    OPENED = :opened
    CLOSED = :closed
    CHANGES = [ OPENED, CLOSED ].freeze

    # key is the tracker's own name for the issue, such as FIR-105, and url its page.
    Report = Data.define(:change, :key, :title, :url) do
      def opened? = change == OPENED
      def closed? = change == CLOSED
    end

    # Whether the tool can open an issue, so whoever offers it can ask how the new issue is to be kept.
    def self.opens?(tool)
      tracker = Provider.for(tool.integration.provider).issue_tracker
      tracker.present? && tracker::OPENS.include?(tool.name)
    end

    # What a tool call that succeeded did to an issue, or nil. A tracker whose answer leaves out what it needs reads
    # through the same connection. The block is handed the switched on tool and its arguments, authorizes the read as
    # whoever made the call and yields to run it, answering the tool's result or nil when it may not.
    def self.report(tool:, environment_row:, arguments:, result:, &authorize)
      tracker = Provider.for(tool.integration.provider).issue_tracker
      return if tracker.nil? || environment_row.nil? || !result.is_a?(Hash) || result["isError"]

      tools = tool.integration.tools.enabled.available.index_by(&:name)
      reader = tracker.new(ConnectionSettings.of(environment_row), tools) do |name, read_arguments, _reads|
        read_tool = tools[name]
        next nil unless read_tool

        authorize.call(read_tool, read_arguments) do
          tool.integration.executor.call(tool: read_tool, environment_row: environment_row, arguments: read_arguments)
        end
      end
      reader.report(tool_name: tool.name, arguments: arguments.to_h.stringify_keys, result: result)
    rescue Integrations::Error => error
      Rails.logger.warn({ event: "issues.unread", provider: tool.integration.provider, error: error.message.truncate(200) }.to_json)
      nil
    end
  end
end
