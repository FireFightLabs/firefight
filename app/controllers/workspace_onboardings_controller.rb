# Stored on the onboarding row so the dialog stays closed on every device. No-op for anyone but the installer.
class WorkspaceOnboardingsController < InertiaController
  def dismiss_dialog
    onboarding = current_workspace.onboarding
    onboarding.dismiss_dialog! if onboarding&.dialog_pending_for?(current_membership)

    redirect_back_or_to dashboard_path
  end
end
