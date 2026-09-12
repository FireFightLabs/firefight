# Every tool a run uses goes through the gateway, so the ledger holds a row before the
# call and its outcome after. params is the binding the ledger stores, so it names what
# was asked and never carries a payload. The step keeps the output, the ledger never does.
class Investigation::ToolCall
  MAX_COMPACTED = 2_000
  MAX_RAW = 200_000

  Result = Data.define(:step, :value)

  def self.run!(investigation, principal:, action_key:, params: {}, hypothesis: nil, reasoning: nil)
    step = investigation.steps.create!(
      hypothesis: hypothesis,
      action_key: action_key,
      params: params,
      reasoning: reasoning,
      status: Investigation::Step::STATUS_RUNNING,
      started_at: Time.current
    )

    begin
      authorization = AbilityGateway.authorize!(
        principal: principal,
        action_key: action_key,
        workspace: investigation.workspace,
        params: params,
        context: {
          source: AbilityGateway::SOURCE_INVESTIGATION,
          incident_id: investigation.incident_id,
          triggered_by_label: investigation.triggered_by.try(:principal_label)
        }
      )
    rescue StandardError => error
      # A refusal is part of the run's record, so the step says so rather than staying open.
      step.fail!(error)
      raise
    end
    step.update!(invocation_id: authorization.invocation_id)

    begin
      value = yield
      authorization.finalize_success!
      text = value.is_a?(String) ? value : value.inspect
      step.succeed!(compacted_result: text.truncate(MAX_COMPACTED), raw_result: text.truncate(MAX_RAW))
      Result.new(step: step, value: value)
    rescue StandardError => error
      authorization.finalize_error!(error)
      step.fail!(error)
      raise
    end
  end
end
