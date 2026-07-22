module Mcp
  # The single seam every MCP tool call flows through: permission check,
  # telemetry, error shaping. The Ability Gateway's authorize! + write-ahead
  # ledger wrap exactly this call site later.
  class ToolDispatcher
    RESOURCE_BY_TOOL = {
      Tools::SEARCH_INCIDENTS => ApiKey::RESOURCE_INCIDENTS,
      Tools::GET_INCIDENT => ApiKey::RESOURCE_INCIDENTS,
      Tools::SEARCH_ALERTS => ApiKey::RESOURCE_ALERTS,
      Tools::SEARCH_CATALOG => ApiKey::RESOURCE_CATALOG,
      Tools::EVALUATE_ROUTING => ApiKey::RESOURCE_POLICIES,
      Tools::SEARCH_RUNBOOKS => ApiKey::RESOURCE_RUNBOOKS,
      Tools::GET_RUNBOOK => ApiKey::RESOURCE_RUNBOOKS
    }.freeze

    def self.call(tool:, server_context:, args:)
      tool_name = tool.name_value
      resource = RESOURCE_BY_TOOL.fetch(tool_name)

      unless server_context[:principal].mcp_readable?(resource)
        return error_response("This token lacks '#{resource}:#{ApiKey::ACTION_READ}' permission.")
      end

      OpenTelemetry::Trace.current_span.add_attributes({ "firefight.mcp.tool" => tool_name })
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = tool.perform(workspace: server_context[:workspace], args: args)
      log_call(tool_name, server_context, started_at)
      response
    rescue ActiveRecord::RecordNotFound
      error_response("Not found in this workspace.")
    end

    def self.error_response(message)
      ::MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
    end

    def self.log_call(tool_name, server_context, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      Rails.logger.info({
        event: "mcp.tool_call",
        tool: tool_name,
        principal: server_context[:principal].principal_label,
        duration_ms: duration_ms
      }.to_json)
    end
  end
end
