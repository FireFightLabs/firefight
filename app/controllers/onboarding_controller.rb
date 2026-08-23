# Interstitial pages between OIDC sign-in and dashboard:
#   - invite_code: new workspace installer needs to claim an invite before install
#   - install:     claimed, ready to add Firefight to Slack
#   - reinstall:   an admin of a disconnected workspace reconnecting it
#   - welcome:     first-install confirmation (letter from founder)
class OnboardingController < InertiaController
  # Onboarding runs before a workspace exists or targets a new one.
  skip_before_action :block_suspended_workspace
  def invite_code
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_install_path) if claimed_invite_code.present?

    render inertia: "onboarding/invite-code", props: {
      teamName: session[:pending_team_name]
    }
  end

  def install
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_invite_code_path) if claimed_invite_code.blank? && !reinstalling?

    render inertia: "onboarding/install", props: {
      teamName: session[:pending_team_name]
    }
  end

  # Reconnecting a workspace that already exists needs no invite code, only
  # an admin of that workspace. The install callback finds the existing
  # workspace by team id and refreshes its tokens in place.
  def reinstall
    return redirect_to(login_path) unless user_signed_in?
    return redirect_to(dashboard_path, alert: "You need admin access to reconnect Slack.") unless current_membership&.admin_access?

    session[:pending_user_id] = current_user.id
    session[:pending_team_id] = current_workspace.platform_id
    session[:pending_team_name] = current_workspace.name
    redirect_to onboarding_install_path
  end

  # show_welcome_note is set in the auth callback on first install only and is
  # consumed here so the founder's letter renders exactly once. Direct visits
  # after onboarding (or refreshes) fall through to the dashboard.
  def welcome
    return redirect_to(login_path) unless user_signed_in?
    return redirect_to(dashboard_path) unless session.delete(:show_welcome_note)

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name
    }
  end

  private

  # The pending team is one Firefight already knows and the signed-in user
  # administers, so this is a reconnect rather than a first install.
  def reinstalling?
    return false unless user_signed_in?

    workspace = Workspace.find_by(platform: :slack, platform_id: session[:pending_team_id])
    workspace.present? && workspace.workspace_memberships.find_by(user: current_user)&.admin_access?
  end
end
