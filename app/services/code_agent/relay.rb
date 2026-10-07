# Relays one model call from a coding agent in the sandbox to the model's provider, as its session allows, and keeps
# what it cost: an Inference row like any other model call, and the session's spend. A call that breaks halfway is still
# counted, and a session makes only a few calls at once, so its budget is never far overshot.
class CodeAgent::Relay
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
      proxy.forward(path: path, body: body, model: @session.model, headers: headers, &)
    ensure
      record(proxy, started)
      @session.end_call!
    end
  end

  private

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
    cost = FirefightAi.cost_micros(@session.model, input: usage.input, output: usage.output, cache_read: usage.cache_read)
    payer = @session.payer
    inference = Inference.create!(
      workspace: @session.workspace, feature: CodeAgentSession::FEATURE, provider: @session.provider, model: @session.model,
      inferable: @session, input_tokens: usage.input, output_tokens: usage.output, cache_read_tokens: usage.cache_read,
      cache_write_tokens: usage.cache_write, cost_micros: cost,
      status: proxy.status.to_i.between?(200, 299) ? Inference::STATUS_SUCCESS : Inference::STATUS_ERROR,
      error_kind: (Inference::ERROR_OUT_OF_CREDIT if proxy.refusal&.out_of_credit?),
      latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
      **payer.ledger
    )
    AiSpend.record!(inference)
    note_account(proxy, payer)
    @session.charge!(cost)
  end

  # A coding agent's call is never retried shorter, so a refusal for credit is the account running out.
  def note_account(proxy, payer)
    if proxy.status.to_i.between?(200, 299)
      payer.answered!(@session.provider)
    elsif proxy.refusal&.out_of_credit?
      payer.own_account? ? payer.account.ran_out!(FirefightAi::OutOfCredit.new) : AiAccount.ran_out!(@session.provider)
    elsif proxy.status.to_i.in?(CodeAgentSession::KEY_REFUSED_STATUSES) && payer.own_account?
      payer.account.key_refused!(FirefightAi::TerminalError.new(reason: AiAccountError::KEY_REASONS.first))
    end
  end
end
