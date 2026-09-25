# One tool call of a run, with how it went, what it returned and the ledger's receipt for it.
class InvestigationStepSerializer < BaseSerializer
  object_as :step

  attributes(position: { type: :number }, status: { type: :string })

  type :string
  def label
    step.shown_label
  end

  # A technical cause, such as a denial or a timeout. The step's own words, never a model's.
  type :string, optional: true
  def failure
    step.error_summary
  end

  # What the tool returned, cut short. The whole output stays encrypted on the step.
  type :string, optional: true
  def result
    step.compacted_result
  end

  type :string, optional: true
  def started_at
    step.started_at&.utc&.iso8601
  end

  type :number, optional: true
  def seconds
    (step.completed_at - step.started_at).round if step.started_at && step.completed_at
  end

  # The ledger row written before the call, whose decision is what let it run.
  type "{ decision: string, at: string } | null"
  def receipt
    step.invocation && { decision: step.invocation.decision, at: step.invocation.created_at.utc.iso8601 }
  end
end
