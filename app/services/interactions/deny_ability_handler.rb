module Interactions
  class DenyAbilityHandler
    def self.execute(interaction)
      AbilityApprovalDecisionHandler.decide(interaction, :deny)
    end
  end
end
