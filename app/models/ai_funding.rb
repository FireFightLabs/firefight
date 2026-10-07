# Who pays for a workspace's model calls, in the order they are tried: its own AI accounts that can pay, by position,
# then the house. The house is the operator's own keys on an install someone runs themselves, unbilled, Firefight's key
# for Firefight's own workspaces, or the workspace's Firefight credits on Firefight's cloud while they can pay.
module AiFunding
  # Each candidate is a FirefightAi::ModelChoice carrying its model, the context with its settings and its payer.
  def self.for(workspace, purpose)
    house_model = FirefightAi.deployment_model_for(purpose, workspace: workspace)
    return [ house_model ] if workspace.nil?

    own = workspace.workspace_ai_accounts.usable.select { |account| account.provider_definition }.map { |account| account.choice_for(purpose) }
    payer = house_payer(workspace)
    payer ? own + [ house_model.with(payer: payer) ] : own
  end

  # What Halon falls back to once every account in the list has been tried, for the settings card.
  def self.fallback_note(workspace)
    case house_payer(workspace)&.paid_by
    when Inference::PAID_BY_OPERATOR then "After these, Halon uses the AI keys this Firefight runs on."
    when Inference::PAID_BY_FIREFIGHT then "After these, Halon uses Firefight's own AI account."
    when Inference::PAID_BY_CREDITS then "After these, Halon uses your Firefight credits."
    else "Halon needs at least one account here that works to answer."
    end
  end

  # The payer after the workspace's own accounts, or nil when there is none.
  def self.house_payer(workspace)
    return AiPayer.house(Inference::PAID_BY_OPERATOR) if Entitlements.ai_account(workspace) == Entitlements::AI_ACCOUNT_OPERATOR
    return AiPayer.house(Inference::PAID_BY_FIREFIGHT) if Entitlements.firefight_pays_for_ai?(workspace)

    AiPayer.house(Inference::PAID_BY_CREDITS) if Entitlements.ai_credit(workspace)&.spendable?
  end
end
