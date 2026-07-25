module Interactions
  class ApproveAbilityHandler
    def self.execute(interaction)
      AbilityApprovalDecisionHandler.decide(interaction, :approve)
    end
  end
end
