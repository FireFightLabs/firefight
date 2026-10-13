module Interactions
  class DenyAbilityHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_APPROVALS, Ability::Action::ACTION_UPDATE

    # Names the request, so someone a workflow's Approval step names may decide it without approvals access.
    def self.authorization_scope(interaction) = Ability::Approval.decision_scope_for(interaction.action_value)

    def self.execute(interaction)
      AbilityApprovalDecisionHandler.decide(interaction, :deny)
    end
  end
end
