# A model call its payer refused for good. The payer is set aside from this call on, and whoever can fix it is told
# once, however many calls were refused together. The AI engine reports each such refusal here.
module AiRefusal
  module_function

  def record!(payer, provider, error)
    return payer.refused!(error) if payer&.own_account?

    house_ran_out!(provider) if FirefightAi::Credit.from(error).out_of_credit?
  end

  # The deployment's own account, whose alert goes to the people running Firefight.
  def house_ran_out!(provider)
    moved = AiAccount.ran_out!(provider)
    AiAccountAlertJob.perform_later(provider.to_s) if moved
    moved
  end
end
