module Mcp
  # Every MCP tool call flows through here. approval_id rides outside the
  # digested params so an approved retry matches the original request.
  class ToolDispatcher
    APPROVAL_ID_ARG = :approval_id
    # Rescued outside the authorized block, so the ledger still records these calls as failed.
    TOOL_ERRORS = [
      Incident::NotActive, Postmortem::StaleContent, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
      ArgumentError, ActionController::ParameterMissing
    ].freeze

    def self.call(tool:, server_context:, args:)
      tool_name = tool.name_value
      workspace = server_context[:workspace]
      resource, crud_action = tool.authorization(workspace, args)

      OpenTelemetry::Trace.current_span.add_attributes({ "firefight.mcp.tool" => tool_name })
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = AbilityGateway.authorize!(
        principal: server_context[:principal],
        action_key: Ability::Action.system_key(resource, crud_action),
        workspace: workspace,
        params: args.except(APPROVAL_ID_ARG),
        context: { source: AbilityGateway::SOURCE_MCP, approval_id: args[APPROVAL_ID_ARG] }
      ) do
        run(tool: tool, workspace: workspace, principal: server_context[:principal], args: args)
      end
      log_call(tool_name, server_context, started_at)
      response
    rescue *TOOL_ERRORS => e
      tool_error_response(e)
    rescue AbilityGateway::Denied
      error_response("This token lacks '#{resource}:#{crud_action}' permission. " \
                     "Token scopes are documented at #{Docs::MCP_SERVER}")
    rescue AbilityGateway::PendingApproval => e
      error_response("Approval required (id: #{e.approval.id}): a workspace #{e.approval.required_role} " \
                     "must approve this call. Retry the identical call with approval_id: \"#{e.approval.id}\" once approved.")
    end

    # Shared with the agent's chat, so a tool behaves the same over MCP and in chat.
    def self.run(tool:, workspace:, principal:, args:)
      if tool.respond_to?(:perform_with_principal)
        tool.perform_with_principal(workspace: workspace, principal: principal, args: args)
      else
        tool.perform(workspace: workspace, args: args)
      end
    end

    def self.tool_error_response(error)
      case error
      when Postmortem::StaleContent
        error_response("This postmortem has changed since the version you read. Read it again with get_postmortem and reapply your edit.")
      when ActiveRecord::RecordNotFound then error_response("Not found in this workspace.")
      when ActiveRecord::RecordInvalid then error_response(error.record.errors.full_messages.to_sentence)
      else error_response(error.message)
      end
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
