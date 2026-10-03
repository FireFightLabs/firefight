# A finding's fix, with its undo once Halon wrote one. The undo is its own serializer class, since one nested in another
# of the same class shares its state and writes over it.
class InvestigationFixPlanSerializer < InvestigationRemediationPlanSerializer
  has_one :undo_plan, as: :undo, serializer: InvestigationRemediationPlanSerializer, optional: true
end
