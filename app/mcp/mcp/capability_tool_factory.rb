module Mcp
  # The capabilities (search_logs, query_metrics, recent_deploys, rollback...) for an outside agent, each answering for
  # anything on the resource map. A call resolves to the provider tool that runs or watches the resource and is authorized,
  # approved and ledgered as that tool's action, the same as calling the tool itself.
  class CapabilityToolFactory
    APPROVAL_ID_ARG = ConnectionToolFactory::APPROVAL_ID_ARG

    # A call waiting for someone to approve it, which is an answer of its own and never a reason to ask elsewhere.
    class Waiting < ::MCP::Tool::Response; end

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
        description: "#{spec.description} (routed to a connection that runs or watches the resource; governed by the Ability Gateway)",
        input_schema: schema,
        annotations: spec.writes ? Tools::Base::WRITE.dup : Tools::Base::READ_ONLY.dup
      ) do |server_context:, **args|
        CapabilityToolFactory.invoke(key, server_context, args)
      end
    end

    def self.invoke(key, server_context, args)
      workspace = server_context[:workspace]
      given = args.except(APPROVAL_ID_ARG).transform_keys(&:to_s)
      return everywhere(key, server_context, args, given) if given[Integrations::Capabilities::CONNECTION_ARG] == Integrations::Capabilities::ALL

      call = Integrations::Capabilities.resolve(workspace, key, given, callable(key, server_context))
      response = invoke_call(call, server_context, approval_id: args[APPROVAL_ID_ARG])
      answer = { content: response.content, structuredContent: response.structured_content, isError: response.error? }
      return response if call.fallback.nil? || response.is_a?(Waiting) || Integrations::Capabilities.definitive?(answer)

      # The gateway uses an approval id only on the call it approved, so the retry carries it to both.
      backup = invoke_call(call.fallback, server_context, approval_id: args[APPROVAL_ID_ARG])
      failure = Array(response.content).filter_map { |part| part[:text] || part["text"] }.join("\n") if response.error?
      ::MCP::Tool::Response.new([ { type: "text", text: Integrations::Capabilities.fell_back(call, failure: failure) }, *Array(backup.content) ],
                                structured_content: backup.structured_content, error: backup.error? && response.error?)
    rescue Integrations::Capabilities::Unroutable => e
      ToolDispatcher.error_response(e.message)
    end

    # Every connection that can answer, each answer headed with where it came from, and each call authorized on its own.
    # An approval belongs to one call, so one that waits is asked again alone once approved. It fails only when every
    # connection did, and each one's structured answer is kept under its connection.
    def self.everywhere(key, server_context, args, given)
      results = Integrations::Capabilities.resolve_all(server_context[:workspace], key, given, callable(key, server_context)).map do |found|
        next [ found.environment_row, ToolDispatcher.error_response(found.reason) ] if found.is_a?(Integrations::Capabilities::Refused)

        [ found.environment_row, invoke_call(found, server_context, approval_id: nil, alone: false) ]
      end
      text = results.map do |row, response|
        Integrations::Capabilities.headed(row, Array(response.content).filter_map { |part| part[:text] || part["text"] }.join("\n"))
      end
      structured = results.filter_map { |row, response| [ Integrations::Capabilities.connection_label(row), response.structured_content ] if response.structured_content }
      ::MCP::Tool::Response.new([ { type: "text", text: text.join("\n\n") } ], structured_content: structured.to_h.presence,
                                error: results.all? { |_row, response| response.error? })
    end

    # The tools this principal may run for the capability, so it is routed only to a connection it can use.
    def self.callable(key, server_context)
      workspace = server_context[:workspace]
      resolved = Ability::Resolver.resolve(server_context[:principal], workspace)
      tools = Integrations::Capabilities.offered(workspace).find { |spec, _tools| spec.key == key }&.last.to_a
      tools.select { |tool| tool.callable_by?(server_context[:principal], resolved) }
    end

    def self.invoke_call(call, server_context, approval_id:, alone: true)
      workspace = server_context[:workspace]
      tool = call.tool

      OpenTelemetry::Trace.current_span.add_attributes({ "firefight.mcp.tool" => tool.action_key })
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = AbilityGateway.authorize!(
        principal: server_context[:principal], action_key: tool.action_key, workspace: workspace, scope: call.scope,
        params: call.arguments, context: { source: AbilityGateway::SOURCE_MCP, approval_id: approval_id }
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
      retry_as = alone ? "Retry the identical call" : "Retry with connection: \"#{call.connection}\" instead of #{Integrations::Capabilities::ALL}"
      text = "Approval required (id: #{e.approval.id}): a workspace #{e.approval.required_role} must approve " \
             "this call. #{retry_as} with approval_id: \"#{e.approval.id}\" once approved."
      Waiting.new([ { type: "text", text: text } ], error: true)
    rescue Integrations::Error => e
      ToolDispatcher.error_response("Upstream tool failed: #{e.message}")
    end
  end
end
