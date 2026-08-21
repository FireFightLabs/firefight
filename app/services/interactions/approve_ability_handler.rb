module Interactions
  class ApproveAbilityHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_APPROVALS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      AbilityApprovalDecisionHandler.decide(interaction, :approve)
    end
  end
end
