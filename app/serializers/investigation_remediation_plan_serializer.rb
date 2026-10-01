# How to fix what a run found.
class InvestigationRemediationPlanSerializer < BaseSerializer
  object_as :plan

  type :string
  def summary = plan.summary

  type :string, optional: true
  def verify = plan.verify

  has_many :steps, serializer: InvestigationRemediationStepSerializer do
    plan.steps
  end
end
