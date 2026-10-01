# The answer a run concluded with, each claim pointing at the steps it rests on.
class InvestigationFindingSerializer < BaseSerializer
  object_as :finding

  attributes(
    summary: { type: :string }, gaps: { type: :string, optional: true }, outcome: { type: :string, optional: true },
    suggests_incident: { type: :boolean }
  )

  type :string, optional: true
  def cause
    finding.winning_hypothesis&.assertion
  end

  has_many :evidence, serializer: InvestigationEvidenceSerializer do
    finding.evidence_items.includes(citations: :source)
  end

  has_one :remediation_plan, as: :fix, serializer: InvestigationRemediationPlanSerializer, optional: true do
    finding.remediation_plan
  end

  # How each thumb was pressed, by outcome.
  type "Record<string, number>"
  def verdicts
    finding.tally
  end
end
