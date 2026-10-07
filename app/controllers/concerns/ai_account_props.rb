# What the AI accounts card draws, on Settings, Workspace and in setup.
module AiAccountProps
  private

  def ai_account_props
    sign_in = AiProviders.sign_in_for(current_workspace)
    {
      aiAccounts: WorkspaceAiAccountSerializer.many(current_workspace.workspace_ai_accounts),
      aiProviders: AiProviderOptionSerializer.many(AiProviders.for_workspace(current_workspace)),
      aiSignIn: sign_in && { label: sign_in.sign_in.label, path: sign_in_ai_accounts_path },
      aiFallback: AiFunding.fallback_note(current_workspace),
      aiCredits: Entitlements.ai_credit(current_workspace)&.summary
    }
  end
end
