# Every tool a run uses goes through the gateway, so the ledger holds a row before the
# call and its outcome after. params is the binding the ledger stores, so it names what
# was asked and never carries a payload. The step keeps the output, the ledger never does.
class Investigation::ToolCall
  MAX_COMPACTED = 2_000
  MAX_RAW = 200_000

  Result = Data.define(:step, :value)

  def self.run!(investigation, action_key:, params: {}, hypothesis: nil, reasoning: nil)
    step = investigation.steps.create!(
      hypothesis: hypothesis,
      action_key: action_key,
      params: params,
      reasoning: reasoning,
      status: Investigation::Step::STATUS_RUNNING,
      started_at: Time.current
    )

    begin
      value = Chat::ToolCall.run!(
        workspace: investigation.workspace,
        principal: investigation.agent_principal,
        action_key: action_key,
        params: params,
        context: investigation.ledger_context
      ) do |authorization|
        step.update!(invocation_id: authorization.invocation_id)
        yield
      end
    rescue StandardError => error
      # A refusal is part of the run's record, so the step says so rather than staying open.
      step.fail!(error)
      raise
    end

    text = value.is_a?(String) ? value : value.inspect
    step.succeed!(compacted_result: text.truncate(MAX_COMPACTED), raw_result: text.truncate(MAX_RAW))
    Result.new(step: step, value: value)
  end
end
