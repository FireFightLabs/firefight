# Relays one model call from a coding agent in the sandbox to the model's provider, as its session allows, and keeps
# what it cost: an Inference row like any other model call, and the session's spend. A call that breaks halfway is still
# counted, and a session makes only a few calls at once, so its budget is never far overshot. The row also says what the
# call was for, from the tools its answer called (CodeAgent::CallKind), and what was cleared from the session it sent.
class CodeAgent::Relay
  # The person's answers to the agent's questions are never cleared from its session, however old.
  KEPT_TOOLS = [ CodeAgent::QuestionTools::ASK, CodeAgent::QuestionTools::WAIT ].freeze

  def initialize(session)
    @session = session
  end

  # Yields what FirefightAi::ModelProxy yields, for the caller to stream back.
  def forward(path:, body:, headers:, &)
    raise FirefightAi::ModelProxy::Refused, CodeAgentSession::OVER_BUDGET if @session.over_budget?

    proxy = FirefightAi::ModelProxy.new(@session.provider, config: @session.llm_config, connect_to: address_check)
    raise FirefightAi::ModelProxy::Refused, CodeAgentSession::TOO_MANY_AT_ONCE unless @session.begin_call!

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      proxy.forward(path: path, body: body, model: @session.model, headers: headers, clearing: clearing, &)
    ensure
      record(proxy, started)
      @session.cleared!(proxy.trim)
      @session.end_call!
    end
  end

  private

  def clearing
    FirefightAi::ModelProxy::Clearing.new(through: @session.cleared_through, server: @session.provider_clears?, kept_tools: KEPT_TOOLS)
  end

  # An address the paying account named is resolved and checked before every call where private networks are refused.
  def address_check
    return nil unless @session.workspace_ai_account&.checks_address_on_each_call?

    lambda do |host|
      Integrations::ModelAddress.ip_for!(host)
    rescue Integrations::ModelAddress::Refused => e
      raise FirefightAi::ModelProxy::Refused, e.message
    end
  end

  def record(proxy, started)
    usage = proxy.usage
    cost = FirefightAi.cost_micros(@session.model, provider: @session.provider, input: usage.input, output: usage.output,
                                   cache_read: usage.cache_read, cache_write: usage.cache_write, cache_write_by_ttl: usage.cache_write_by_ttl)
    payer = @session.payer
    inference = Inference.create!(
      workspace: @session.workspace, feature: CodeAgentSession::FEATURE, provider: @session.provider, model: @session.model,
      inferable: @session, input_tokens: usage.input, output_tokens: usage.output, cache_read_tokens: usage.cache_read,
      cache_write_tokens: usage.cache_write, cache_write_tokens_by_ttl: usage.cache_write_by_ttl, cost_micros: cost,
      status: proxy.status.to_i.between?(200, 299) ? Inference::STATUS_SUCCESS : Inference::STATUS_ERROR,
      error_kind: (Inference::ERROR_OUT_OF_CREDIT if proxy.refusal&.out_of_credit?),
      latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
      provider_request_id: proxy.request_id, agent_call: agent_call(proxy), **payer.ledger
    )
    AiSpend.record!(inference)
    note_account(proxy, payer)
    @session.charge!(cost)
  end

  # What the call was for and what its session had cleared. Only tool names and kinds, never what a tool was given.
  def agent_call(proxy)
    calls = proxy.calls.to_a
    trim = proxy.trim
    provider = proxy.calls.cleared
    {
      "kinds" => CodeAgent::CallKind.of(calls), "tools" => calls.map(&:name),
      "conversation" => trim&.conversation, "cleared" => trim&.count.to_i, "clearedByProvider" => trim&.by_provider == true,
      "providerRefusedClearing" => trim&.provider_refused == true,
      "providerCleared" => (provider && { "toolUses" => provider.tool_uses, "inputTokens" => provider.input_tokens })
    }.compact
  end

  # A coding agent's call is never retried shorter, so a refusal for credit is the account running out.
  def note_account(proxy, payer)
    if proxy.status.to_i.between?(200, 299)
      payer.answered!(@session.provider)
    elsif proxy.refusal&.out_of_credit?
      payer.own_account? ? AiRefusal.account_ran_out!(payer.account, FirefightAi::OutOfCredit.new) : AiRefusal.house_ran_out!(@session.provider)
    elsif proxy.status.to_i.in?(CodeAgentSession::KEY_REFUSED_STATUSES) && payer.own_account?
      AiRefusal.key_refused!(payer.account, FirefightAi::TerminalError.new(reason: FirefightAi::KEY_REFUSED_REASONS.first))
    end
  end
end
