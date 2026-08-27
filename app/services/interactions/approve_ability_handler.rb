module Interactions
  class ApproveAbilityHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      AbilityApprovalDecisionHandler.decide(interaction, :approve)
    end
  end
end
