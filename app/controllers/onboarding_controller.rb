class OnboardingController < InertiaController
  ALREADY_CONNECTED_MESSAGE = "Slack is already connected to this workspace.".freeze

  # Connecting Slack changes the workspace, which only its admins may do.
  authorizes Ability::Action::RESOURCE_WORKSPACE, update: :connect_slack

  # Onboarding runs before a workspace exists or targets a new one.
  skip_before_action :block_inaccessible_workspace
  skip_before_action :require_authentication, except: [ :welcome, :reinstall, :connect_slack ]
  skip_before_action :continue_setup
  def invite_code
    return redirect_to(login_path) if session[:pending_team_id].blank?
    return redirect_to(onboarding_install_path) if !InviteCode.required? || claimed_invite_code.present?

    render inertia: "onboarding/invite-code", props: {
      teamName: session[:pending_team_name]
    }
  end

  # Connecting a workspace may not know its Slack team yet, and then Slack asks which one.
  def install
    connecting = connecting_workspace
    return redirect_to(login_path) if session[:pending_team_id].blank? && connecting.nil?
    return redirect_to(onboarding_invite_code_path) if connecting.nil? && InviteCode.required? && claimed_invite_code.blank? && !reinstalling?

    render inertia: "onboarding/install", props: {
      teamName: session[:pending_team_name].presence || connecting&.name,
      skipPath: connecting && dashboard_path
    }
  end

  # For a workspace that started without Slack. The install callback fills this workspace rather than creating one.
  def connect_slack
    return redirect_to(dashboard_path, alert: ALREADY_CONNECTED_MESSAGE) if current_workspace.chat_connected?

    team_id = session[:pending_team_id] if session[:connecting_workspace_id] == current_workspace.id
    session[:connecting_workspace_id] = current_workspace.id
    session[:pending_user_id] = current_user.id
    session[:pending_team_id] = team_id
    session[:pending_team_name] = nil
    redirect_to onboarding_install_path
  end

  # Reconnecting needs no invite code, only an admin. The install callback finds the
  # workspace by team id and refreshes its tokens in place.
  def reinstall
    return redirect_to(dashboard_path, alert: "You need admin access to reconnect Slack.") unless current_membership&.admin_access?

    session.delete(:connecting_workspace_id)
    session[:pending_user_id] = current_user.id
    session[:pending_team_id] = current_workspace.platform_id
    session[:pending_team_name] = current_workspace.name
    redirect_to onboarding_install_path
  end

  # Set in the auth callback on first install, or when a workspace is created, and consumed here, so the founder's
  # letter renders exactly once. A workspace created from a Slack sign-in goes on to connect that team.
  def welcome
    return redirect_to(dashboard_path) unless session.delete(:show_welcome_note)

    render inertia: "onboarding/welcome", props: {
      userName: current_user.name,
      workspaceName: current_workspace.name,
      connectSlack: connecting_workspace == current_workspace && session[:pending_team_id].present?
    }
  end

  private

  def connecting_workspace
    id = session[:connecting_workspace_id]
    current_user&.workspaces&.find_by(id: id) if id
  end

  # The pending team is one Firefight knows and the user administers, so this is a reconnect.
  def reinstalling?
    return false unless user_signed_in?

    workspace = Workspace.find_by(platform: :slack, platform_id: session[:pending_team_id])
    workspace.present? && workspace.workspace_memberships.find_by(user: current_user)&.admin_access?
  end
end
