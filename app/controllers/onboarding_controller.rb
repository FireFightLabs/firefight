# Interstitial pages between OIDC sign-in and dashboard:
#   - invite_code: new workspace installer needs to claim an invite before install
#   - install:     claimed, ready to add Firefight to Slack
#   - welcome:     first-install confirmation (letter from founder)
class OnboardingController < InertiaController
  def invite_code
    return redirect_to(login_path) if session[:pending_team_id].blank?
    # Already have a valid claim — no reason to show this screen again.
    return redirect_to(onboarding_install_path) if claimed_invite_code.present?

    render inertia: "onboarding/invite-code", props: {
      teamName: session[:pending_team_name]
    }
  end

  def install
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_invite_code_path) if claimed_invite_code.blank?

    render inertia: "onboarding/install", props: {
      teamName: session[:pending_team_name],
      teamId: session[:pending_team_id]
    }
  end

  def welcome
    return redirect_to(login_path) unless user_signed_in?

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name
    }
  end
end
