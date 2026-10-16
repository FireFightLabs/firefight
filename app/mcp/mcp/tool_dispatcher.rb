module Mcp
  # Every MCP tool call flows through here. approval_id rides outside the
  # digested params so an approved retry matches the original request. A write-only argument reaches the ledger only as
  # its digest (Tools::Base.ledger_params).
  class ToolDispatcher
    APPROVAL_ID_ARG = :approval_id
    # Rescued outside the authorized block, so the ledger still records these calls as failed.
    TOOL_ERRORS = [
      Incident::NotActive, Incident::CreationBlocked, Postmortem::StaleContent, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
      ArgumentError, ActionController::ParameterMissing, HandbookService::Blocked
    ].freeze

    def self.call(tool:, server_context:, args:)
      tool_name = tool.name_value
      workspace = server_context[:workspace]
      return error_response("There is no tool called #{tool_name} in this workspace.") unless tool.offered_in?(workspace)

      resource, crud_action = tool.authorization(workspace, args)
      principal = server_context[:principal]
      refusal = tool.token_refusal(workspace, args)
      return error_response(refusal) if refusal
      if tool.mints_token?(workspace, args) && !TokenHandoff.reachable?(principal, workspace)
        return error_response(TokenHandoff::UNREACHABLE)
      end

      OpenTelemetry::Trace.current_span.add_attributes({ "firefight.mcp.tool" => tool_name })
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = AbilityGateway.authorize!(
        principal: server_context[:principal],
        action_key: Ability::Action.system_key(resource, crud_action),
        workspace: workspace,
        params: tool.ledger_params(args.except(APPROVAL_ID_ARG)),
        context: { source: AbilityGateway::SOURCE_MCP, approval_id: args[APPROVAL_ID_ARG], asks_a_person: tool.asks_a_person? },
        holdable: tool.holdable? || tool.asks_a_person?
      ) do |authorization|
        answered = run(tool: tool, workspace: workspace, principal: principal, args: args,
                       hand_token: ->(token) { TokenHandoff.to_person!(token, principal: principal, workspace: workspace) })
        authorization.answer_failed!(text_of(answered)) if answered.error?
        answered
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

    # Shared with the agent's chat, so a tool behaves the same over MCP and in chat. by_halon is true only from Halon's
    # chat, for a tool whose post names who wrote it.
    # hand_token takes a token the tool minted and answers what is said in its place, since a token never reaches a model.
    # Without one nobody can be shown it, so it is switched off.
    def self.run(tool:, workspace:, principal:, args:, hand_token: nil, by_halon: false)
      answered =
        if tool.respond_to?(:perform_with_principal)
          named = tool.respond_to?(:names_halon?) && tool.names_halon? ? { by_halon: by_halon } : {}
          tool.perform_with_principal(workspace: workspace, principal: principal, args: args, **named)
        else
          tool.perform(workspace: workspace, args: args)
        end
      token = answered.structured_content.is_a?(Hash) && answered.structured_content[:token]
      return answered if token.blank?
      return error_response(TokenHandoff.discard!(token)) unless hand_token

      token_withheld(answered, handed(token, hand_token))
    rescue TokenHandoff::Undelivered => e
      error_response(e.message)
    end

    # A handoff that breaks before the person has the token switches it off, so no token nobody saw stays live.
    def self.handed(token, hand_token)
      hand_token.call(token)
    rescue TokenHandoff::Undelivered
      raise
    rescue StandardError
      TokenHandoff.discard!(token)
      raise
    end
    private_class_method :handed

    def self.token_withheld(answered, words)
      payload = answered.structured_content.merge(token: words)
      ::MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ], structured_content: payload)
    end
    private_class_method :token_withheld

    def self.tool_error_response(error)
      case error
      when Postmortem::StaleContent
        error_response("This postmortem has changed since the version you read. Read it again with get_postmortem and reapply your edit.")
      when ActiveRecord::RecordNotFound then error_response("Not found in this workspace.")
      when ActiveRecord::RecordInvalid then error_response(error.record.errors.full_messages.to_sentence)
      else error_response(error.message)
      end
    end

    def self.text_of(response) = Array(response.content).filter_map { |part| part[:text] || part["text"] }.join("\n")

    # A connected tool that answers with its own error ran, and failed, so the ledger says so.
    def self.ledger_failure(authorization, answer)
      return unless answer["isError"] == true

      authorization.answer_failed!(text_of(::MCP::Tool::Response.new(answer["content"])))
    end

    # One of Firefight's own rules refused the call, such as a push to a protected branch. The agent is told it is
    # Firefight's and final rather than the provider failing, and the ledger records it as refused.
    REFUSED = "refused".freeze

    def self.refused(authorization, reason)
      authorization.answer_refused!(reason)
      { "content" => [ { "type" => "text", "text" => "#{FirefightAi::Evidence::REFUSED_BY_RULE} #{reason}" } ], "isError" => true, REFUSED => true }
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
