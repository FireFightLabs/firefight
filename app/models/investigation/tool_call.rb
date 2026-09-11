# Every tool a run uses goes through the gateway, so the ledger holds a row before the
# call and its outcome after. The step keeps the output, the ledger never does.
class Investigation::ToolCall
  MAX_COMPACTED = 2_000
  MAX_RAW = 200_000

  Result = Data.define(:step, :value)

  def self.run!(investigation, principal:, action_key:, params: {}, hypothesis: nil, reasoning: nil)
    step = investigation.investigation_steps.create!(
      hypothesis: hypothesis,
      position: investigation.next_step_position,
      action_key: action_key,
      params: params,
      reasoning: reasoning,
      status: InvestigationStep::STATUS_RUNNING,
      started_at: Time.current
    )

    begin
      authorization = AbilityGateway.authorize!(
        principal: principal,
        action_key: action_key,
        workspace: investigation.workspace,
        params: params,
        context: {
          incident_id: investigation.incident_id,
          triggered_by_label: investigation.triggered_by.try(:principal_label)
        }
      )
    rescue StandardError => error
      # A refusal is part of the run's record, so the step says so rather than staying open.
      step.fail!(error)
      raise
    end
    step.update!(invocation_id: authorization.invocation&.id)

    begin
      value = yield
      authorization.finalize_success!
      step.succeed!(compacted_result: compact(value), raw_result: raw(value))
      Result.new(step: step, value: value)
    rescue StandardError => error
      authorization.finalize_error!(error)
      step.fail!(error)
      raise
    end
  end

  # What the running context sees. The full output stays on the step.
  def self.compact(value)
    text(value).truncate(MAX_COMPACTED)
  end
  private_class_method :compact

  def self.raw(value)
    text(value).truncate(MAX_RAW)
  end
  private_class_method :raw

  def self.text(value)
    value.is_a?(String) ? value : value.inspect
  end
  private_class_method :text
end
