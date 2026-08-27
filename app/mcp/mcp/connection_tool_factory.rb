module Mcp
  # Exposes a workspace's allowlisted connection tools through Firefight's
  # own MCP server. The same registry, outward. Every call flows through
  # AbilityGateway (grant + config + approvals + ledger) and then the
  # integration's executor with the resolved environment's credentials.
  class ConnectionToolFactory
    ENVIRONMENT_ARG = :environment
    APPROVAL_ID_ARG = :approval_id

    # Lists only what the principal could actually call, so a narrowly
    # scoped service key never receives an inventory of the workspace's
    # connections. Calls are still authorized individually in invoke.
    def self.tools_for(workspace, principal)
      resolved = Ability::Resolver.resolve(principal)

      Integration::Tool.enabled.available
                       .joins(:integration)
                       .where(integrations: { workspace_id: workspace.id, disabled_at: nil, deleted_at: nil })
                       .includes(:integration, :ability_action)
                       .select { |tool| callable?(tool, principal, resolved) }
                       .map { |tool| build(tool) }
    end

    def self.callable?(tool, principal, resolved)
      return true if resolved.action_keys.include?(tool.action_key)

      tool.ability_action.present? && principal.implicitly_allowed?(tool.ability_action)
    end

    def self.build(tool)
      tool_id = tool.id
      ::MCP::Tool.define(
        name: tool.action_key.tr(".", "_"),
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

      environment_entry = nil
      if args[ENVIRONMENT_ARG].present?
        environment_entry = workspace.catalog_entries.active.find_by(slug: args[ENVIRONMENT_ARG].to_s)
        return ToolDispatcher.error_response("Unknown environment '#{args[ENVIRONMENT_ARG]}'.") unless environment_entry
      end

      scope = environment_entry ? { "environment" => environment_entry.id } : {}
      arguments = args.except(ENVIRONMENT_ARG, APPROVAL_ID_ARG).transform_keys(&:to_s)

      # Same telemetry as a static tool, so connection calls show up in the
      # mcp.tool_call log and the span like everything else the server does.
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

    # When the connection is wired per environment and none was named, the
    # deny is really "pick one" - so say which. Slugs are catalog data any
    # member can read, and naming one still has to pass the grant and config
    # checks, so nothing is disclosed that the caller could not already see.
    def self.environment_hint(tool)
      integration = tool.integration
      return "" if integration.resolve_environment(nil).present?

      slugs = integration.integration_environments.enabled.includes(:environment)
                         .filter_map { |row| row.environment&.slug }
      return "" if slugs.size < 2

      " This connection is wired per environment. Retry with environment set to one of: #{slugs.join(', ')}."
    end

    def self.description_for(tool)
      base = tool.description.presence || "#{tool.name} on #{tool.integration.name}"
      "#{base} (via the #{tool.integration.name} connection; governed by the Ability Gateway)"
    end

    # The remote schema plus Firefight's routing args, which environment's
    # credentials to use, and the approval retry handle.
    def self.augmented_schema(tool)
      schema = (tool.params_schema.presence || { "type" => "object" }).deep_dup
      schema["properties"] = (schema["properties"] || {}).merge(
        ENVIRONMENT_ARG.to_s => { "type" => "string", "description" => "Environment slug (e.g. production); omit when the connection has one environment" },
        APPROVAL_ID_ARG.to_s => { "type" => "string", "description" => "Approval id when retrying an approved call" }
      )
      schema
    end
  end
end
