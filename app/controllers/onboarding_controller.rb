class OnboardingController < InertiaController
  # Onboarding runs before a workspace exists or targets a new one.
  skip_before_action :block_suspended_workspace
  skip_before_action :require_authentication, except: [ :welcome, :reinstall ]
  def invite_code
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_install_path) if !InviteCode.required? || claimed_invite_code.present?

    render inertia: "onboarding/invite-code", props: {
      teamName: session[:pending_team_name]
    }
  end

  def install
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_invite_code_path) if InviteCode.required? && claimed_invite_code.blank? && !reinstalling?

    render inertia: "onboarding/install", props: {
      teamName: session[:pending_team_name]
    }
  end

  # Reconnecting needs no invite code, only an admin. The install callback finds the
  # workspace by team id and refreshes its tokens in place.
  def reinstall
    return redirect_to(dashboard_path, alert: "You need admin access to reconnect Slack.") unless current_membership&.admin_access?

    session[:pending_user_id] = current_user.id
    session[:pending_team_id] = current_workspace.platform_id
    session[:pending_team_name] = current_workspace.name
    redirect_to onboarding_install_path
  end

  # Set in the auth callback on first install and consumed here, so the founder's letter renders exactly once.
  def welcome
    return redirect_to(dashboard_path) unless session.delete(:show_welcome_note)

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name
    }
  end

  private

  # The pending team is one Firefight knows and the user administers, so this is a reconnect.
  def reinstalling?
    return false unless user_signed_in?

    workspace = Workspace.find_by(platform: :slack, platform_id: session[:pending_team_id])
    workspace.present? && workspace.workspace_memberships.find_by(user: current_user)&.admin_access?
  end
end
