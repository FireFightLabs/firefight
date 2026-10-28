# What the AI accounts card draws, on Settings, Workspace and in setup.
module AiAccountProps
  # What a check on a waiting subscription sign-in reads back: the sign-in, gone once it finished, and the accounts.
  SIGN_IN_READ_BACK = { "ACCOUNTS" => "aiAccounts", "SUBSCRIPTION_SIGN_IN" => "aiSubscriptionSignIn" }.freeze

  private

  def ai_account_props
    sign_in = AiProviders.sign_in_for(current_workspace)
    {
      SIGN_IN_READ_BACK.fetch("ACCOUNTS").to_sym => WorkspaceAiAccountSerializer.many(current_workspace.workspace_ai_accounts),
      aiProviders: AiProviderOptionSerializer.many(AiProviders.for_workspace(current_workspace)),
      aiSignIn: sign_in && { label: sign_in.sign_in.label, path: sign_in_ai_accounts_path },
      aiSubscriptions: AiSubscriptionOptionSerializer.many(AiSubscriptions.offered),
      SIGN_IN_READ_BACK.fetch("SUBSCRIPTION_SIGN_IN").to_sym => subscription_sign_in,
      aiFallback: AiFunding.fallback_note(current_workspace),
      aiCredits: Entitlements.ai_credit(current_workspace)&.summary
    }
  end

  # The sign-in this person has waiting, which the card shows until it finishes.
  def subscription_sign_in
    waiting = SubscriptionSignIn.waiting.where(workspace: current_workspace, started_by: current_membership).order(:created_at).last
    waiting && SubscriptionSignInSerializer.one(waiting)
  end
end
