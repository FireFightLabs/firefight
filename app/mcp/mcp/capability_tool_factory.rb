module Mcp
  # The capabilities (search_logs, query_metrics, recent_deploys, rollback...) for an outside agent, each answering for
  # anything on the resource map. A call resolves to the provider tool that holds the resource and is authorized,
  # approved and ledgered as that tool's action, the same as calling the tool itself.
  class CapabilityToolFactory
    APPROVAL_ID_ARG = ConnectionToolFactory::APPROVAL_ID_ARG

    # Only what the principal could call through at least one connection, and invoke still authorizes each call.
    def self.tools_for(workspace, principal)
      resolved = Ability::Resolver.resolve(principal, workspace)

      Integrations::Capabilities.offered(workspace).filter_map do |spec, tools|
        callable = tools.select { |tool| tool.callable_by?(principal, resolved) }
        build(spec, callable) if callable.any?
      end
    end

    def self.build(spec, tools)
      schema = Integrations::Capabilities.schema(spec, Integrations::Capabilities.connections(tools))
      schema["properties"] = schema["properties"].merge(APPROVAL_ID_ARG.to_s => { "type" => "string", "description" => "Approval id when retrying an approved call" })
      key = spec.key
      ::MCP::Tool.define(
        name: spec.tool_name,
        description: "#{spec.description} (routed to the connection that holds the resource; governed by the Ability Gateway)",
        input_schema: schema,
        annotations: spec.writes ? Tools::Base::WRITE.dup : Tools::Base::READ_ONLY.dup
      ) do |server_context:, **args|
        CapabilityToolFactory.invoke(key, server_context, args)
      end
    end

    def self.invoke(key, server_context, args)
      workspace = server_context[:workspace]
      given = args.except(APPROVAL_ID_ARG).transform_keys(&:to_s)
      call = Integrations::Capabilities.resolve(workspace, key, given)
      tool = call.tool

      OpenTelemetry::Trace.current_span.add_attributes({ "firefight.mcp.tool" => tool.action_key })
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = AbilityGateway.authorize!(
        principal: server_context[:principal], action_key: tool.action_key, workspace: workspace, scope: call.scope,
        params: call.arguments, context: { source: AbilityGateway::SOURCE_MCP, approval_id: args[APPROVAL_ID_ARG] }
      ) do
        answer = tool.integration.executor.call(
          tool: tool, environment_row: call.environment_row, arguments: call.arguments, box_key: server_context[:principal].code_box_key
        )
        call.present_result(answer)
      end
      ToolDispatcher.log_call(tool.action_key, server_context, started_at)

      ::MCP::Tool::Response.new(result["content"], structured_content: result["structuredContent"], error: result["isError"] == true)
    rescue Integrations::Capabilities::Unroutable => e
      ToolDispatcher.error_response(e.message)
    rescue AbilityGateway::Denied
      ToolDispatcher.error_response("No grant covers '#{tool.action_key}' here. Token scopes are documented at #{Docs::MCP_SERVER}")
    rescue AbilityGateway::PendingApproval => e
      ToolDispatcher.error_response(
        "Approval required (id: #{e.approval.id}): a workspace #{e.approval.required_role} must approve " \
        "this call. Retry the identical call with approval_id: \"#{e.approval.id}\" once approved."
      )
    rescue Integrations::Error => e
      ToolDispatcher.error_response("Upstream tool failed: #{e.message}")
    end
  end
end
