module Interactions
  class DenyAbilityHandler
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_APPROVALS, ApiKey::ACTION_UPDATE

    def self.execute(interaction)
      AbilityApprovalDecisionHandler.decide(interaction, :deny)
    end
  end
end
