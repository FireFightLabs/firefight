# What a model call costs whoever paid for it. A call on Firefight credits is charged by the hosted build's backend,
# which answers what it billed. Every other payer is billed nothing here. A workspace's own account is billed by its
# provider, the operator pays their own provider, and Firefight pays for its own workspaces.
module AiSpend
  def self.record!(inference)
    return unless inference.paid_by == Inference::PAID_BY_CREDITS

    billed = Entitlements.charge_ai!(inference)
    inference.update_column(:billed_micros, billed) if billed
  end
end
