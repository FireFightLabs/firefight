module Mcp
  # Exposes a workspace's allowlisted connection tools through Firefight's own
  # MCP server. Every call flows through AbilityGateway, then the integration's executor.
  class ConnectionToolFactory
    ENVIRONMENT_ARG = Integration::Tool::ENVIRONMENT_ARG.to_sym
    APPROVAL_ID_ARG = :approval_id

    # Lists only what the principal could call, so a narrowly scoped service key
    # never sees an inventory of the workspace's connections. invoke still authorizes each call.
    def self.tools_for(workspace, principal)
      resolved = Ability::Resolver.resolve(principal, workspace)

      Integration::Tool.in_workspace(workspace)
                       .select { |tool| tool.callable_by?(principal, resolved) }
                       .map { |tool| build(tool) }
    end

    def self.build(tool)
      tool_id = tool.id
      ::MCP::Tool.define(
        name: tool.model_facing_name,
        description: description_for(tool),
        input_schema: augmented_schema(tool),
        annotations: tool.read_only? ? Tools::Base::READ_ONLY.dup : Tools::Base::WRITE.dup
      ) do |server_context:, **args|
        ConnectionToolFactory.invoke(tool_id, server_context, args)
      end
    end

    def self.invoke(tool_id, server_context, args)
      tool = Integration::Tool.find(tool_id)
      workspace = server_context[:workspace]

      begin
        environment_entry = tool.integration.environment_entry_for(args[ENVIRONMENT_ARG])
      rescue Integration::UnknownEnvironment => e
        return ToolDispatcher.error_response(e.message)
      end

      scope = environment_entry ? { "environment" => environment_entry.id } : {}
      arguments = args.except(ENVIRONMENT_ARG, APPROVAL_ID_ARG).transform_keys(&:to_s)

      # Same telemetry as a static tool.
      OpenTelemetry::Trace.current_span.add_attributes({ "firefight.mcp.tool" => tool.action_key })
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = AbilityGateway.authorize!(
        principal: server_context[:principal], action_key: tool.action_key,
        workspace: workspace, scope: scope, params: arguments,
        context: { source: AbilityGateway::SOURCE_MCP, approval_id: args[APPROVAL_ID_ARG] }
      ) do
        environment_row = tool.integration.resolve_environment(environment_entry&.id)
        tool.integration.executor.call(tool: tool, environment_row: environment_row, arguments: arguments)
      end
      ToolDispatcher.log_call(tool.action_key, server_context, started_at)

      ::MCP::Tool::Response.new(
        result["content"],
        structured_content: result["structuredContent"],
        error: result["isError"] == true
      )
    rescue AbilityGateway::Denied
      ToolDispatcher.error_response(
        "No grant covers '#{tool.action_key}' here (or the connection is not wired for this environment). " \
        "Token scopes are documented at #{Docs::MCP_SERVER}#{environment_hint(tool)}"
      )
    rescue AbilityGateway::PendingApproval => e
      ToolDispatcher.error_response(
        "Approval required (id: #{e.approval.id}): a workspace #{e.approval.required_role} must approve " \
        "this call. Retry the identical call with approval_id: \"#{e.approval.id}\" once approved."
      )
    rescue Integrations::Error => e
      ToolDispatcher.error_response("Upstream tool failed: #{e.message}")
    end

    # A deny for a missing environment really means "pick one", so name them.
    def self.environment_hint(tool)
      slugs = tool.integration.environment_choices
      return "" if slugs.empty?

      " This connection is wired per environment. Retry with environment set to one of: #{slugs.join(', ')}."
    end

    def self.description_for(tool)
      base = tool.description.presence || "#{tool.name} on #{tool.integration.name}"
      "#{base} (via the #{tool.integration.name} connection; governed by the Ability Gateway)"
    end

    # The schema the agent is handed, plus the approval id only an outside client retries with.
    def self.augmented_schema(tool)
      schema = tool.offered_schema
      schema["properties"] = schema["properties"].merge(
        APPROVAL_ID_ARG.to_s => { "type" => "string", "description" => "Approval id when retrying an approved call" }
      )
      schema
    end
  end
end
