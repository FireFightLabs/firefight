# Transcript access is here rather than on Permissions on purpose. A grant says who
# may ask, this says whether the conversation is readable at all.
class WorkspaceSettingsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: :update

  def show
    sign_in = AiProviders.sign_in_for(current_workspace)
    render inertia: "settings/workspace", props: {
      settings: WorkspaceSettingsSerializer.one(current_workspace),
      issueWebhookUrl: current_workspace.issue_webhook_token && api_v1_issue_events_url(current_workspace.issue_webhook_token),
      aiAccounts: WorkspaceAiAccountSerializer.many(current_workspace.workspace_ai_accounts),
      aiProviders: AiProviderOptionSerializer.many(AiProviders.for_workspace(current_workspace)),
      aiSignIn: sign_in && { label: sign_in.sign_in.label, path: sign_in_ai_accounts_path },
      aiFallback: AiFunding.fallback_note(current_workspace),
      aiCredits: Entitlements.ai_credit(current_workspace)&.summary
    }
  end

  # A blank retention casts to null, which means keep everything.
  def update
    IssueSyncService.new(current_workspace).update_settings!(params.permit(*Workspace::Settings::PERMITTED), by: current_membership)

    redirect_to settings_workspace_path, notice: "Workspace settings were updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end
end
