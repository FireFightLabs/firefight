# Every method starts a session the same way, with a fresh session id and the page the person was sent away from
# kept across the reset.
module SignInSession
  extend ActiveSupport::Concern

  private

  def start_session(user_id:, workspace_id:)
    return_to = safe_return_to(session[:return_to])
    reset_session
    session[:user_id] = user_id
    session[:workspace_id] = workspace_id
    return_to
  end

  # Signed in through Google or email. A person with no workspace yet goes on to name one, and someone Firefight has
  # never seen is made only once they do.
  def finish_self_serve_sign_in(result)
    membership = result.user&.workspace_memberships&.order(joined_at: :desc)&.first
    unless membership
      return start_signup(user: result.user, claims: result.claims, method: result.identity&.provider || result.claims&.provider)
    end

    return_to = start_session(user_id: membership.user_id, workspace_id: membership.workspace_id)
    redirect_to(return_to || dashboard_path)
  end

  # Someone who signed in and belongs to no workspace, held as the person or, for someone new, as what the provider
  # verified about them. They are not signed in to the dashboard until they create a workspace. A Slack sign-in brings
  # the team it came from, which names the workspace and is the one it later connects. method is the UserIdentity
  # provider they signed in with.
  def start_signup(method:, user: nil, claims: nil, team_id: nil, team_name: nil)
    reset_session
    session[:signup_method] = method
    session[:signup_user_id] = user&.id
    session[:signup_claims] = claims.to_h.transform_keys(&:to_s) if user.nil? && claims
    session[:signup_team_id] = team_id
    session[:signup_team_name] = team_name
    redirect_to signup_workspace_path
  end

  # A Slack sign-in from a team no workspace has yet, by someone who chose a workspace of theirs without Slack, carries
  # on in that workspace rather than making another. Its setup keeps its progress, and connecting Slack connects the
  # team they signed in with. It goes where a new workspace goes, so one with no plan yet chooses one first.
  def continue_in_unconnected(membership, team_id:, team_name:)
    start_session(user_id: membership.user_id, workspace_id: membership.workspace_id)
    hold_team_to_connect(membership, team_id: team_id, team_name: team_name)
    session[:reused_workspace_id] = membership.workspace_id
    redirect_to(Entitlements.next_step_path(membership.workspace) || onboarding_welcome_path)
  end

  # Connecting Slack to this workspace next accepts only this team (SlackAuthenticationService#handle_install).
  def hold_team_to_connect(membership, team_id:, team_name:)
    session[:connecting_workspace_id] = membership.workspace_id
    session[:pending_user_id] = membership.user_id
    session[:pending_team_id] = team_id
    session[:pending_team_name] = team_name
  end

  def safe_return_to(path)
    return nil if path.blank?
    return nil unless path.is_a?(String) && path.start_with?("/app/")

    path
  end
end
