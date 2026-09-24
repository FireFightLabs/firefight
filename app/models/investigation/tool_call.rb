# Every tool a run uses goes through the gateway, so the ledger holds a row before the
# call and its outcome after. params is the binding the ledger stores, so it names what
# was asked and never carries a payload. The step keeps the output, the ledger never does.
class Investigation::ToolCall
  MAX_COMPACTED = 2_000
  MAX_RAW = 200_000

  Result = Data.define(:step, :value)

  NOT_RECORDED = "This call was not made in the run being replayed, so it has no recorded result.".freeze

  def self.run!(investigation, action_key:, params: {}, scope: {}, hypothesis: nil, reasoning: nil, tool_name: nil, label: nil)
    step = numbered_step(
      investigation,
      tool_name: tool_name, label: label, hypothesis: hypothesis, action_key: action_key, params: params,
      reasoning: reasoning, status: Investigation::Step::STATUS_RUNNING, started_at: Time.current
    )

    begin
      value = Chat::ToolCall.run!(
        workspace: investigation.workspace,
        principal: investigation.acting_principal,
        action_key: action_key,
        params: params,
        scope: scope,
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

  # The same call made in the same order gets what the replayed run got, failure included, so only the reasoning
  # differs. A call that run never made is answered with NOT_RECORDED and counts as where the two runs parted.
  def self.replay!(investigation, action_key:, params: {}, tool_name: nil, label: nil)
    asked = params.to_h.deep_stringify_keys
    same = ->(step) { step.action_key == action_key && step.params == asked }
    already = investigation.steps.count(&same)
    recorded = investigation.replay_of.steps.select(&same)[already]
    step = numbered_step(
      investigation, tool_name: tool_name, label: label, action_key: action_key, params: asked,
      status: Investigation::Step::STATUS_RUNNING, started_at: Time.current
    )
    Result.new(step: step, value: replayed(step, recorded, action_key))
  end

  def self.replayed(step, recorded, action_key)
    if recorded.nil?
      step.fail!(NOT_RECORDED)
      NOT_RECORDED
    elsif recorded.status == Investigation::Step::STATUS_SUCCEEDED
      step.succeed!(compacted_result: recorded.compacted_result, raw_result: recorded.raw_result)
      recorded.raw_result || recorded.compacted_result
    else
      step.fail!(recorded.error_summary.to_s)
      "#{action_key} failed: #{recorded.error_summary}"
    end
  end
  private_class_method :replayed

  # The number is read and then written, so two calls at once could pick the same one. The unique
  # index refuses the second, which takes the next number.
  def self.numbered_step(investigation, **attributes)
    investigation.steps.create!(position: investigation.next_step_position, **attributes)
  rescue ActiveRecord::RecordNotUnique
    retry
  end
  private_class_method :numbered_step
end
