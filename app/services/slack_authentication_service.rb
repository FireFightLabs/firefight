# Orchestrates Slack auth callbacks. Returns AuthOutcome describing what the
# controller should do next. Decision logic lives here; HTTP concerns stay in
# the controller; state changes happen on the models.
class SlackAuthenticationService
  # OIDC sign-in (identity only). Decides between signed_in / install_needed /
  # invite_needed based on workspace existence, membership, and pending invites.
  def handle_openid_signin(auth_hash, pending_invitation_id: nil)
    email     = auth_hash.info.email
    team_id   = auth_hash.info.team_id
    team_name = auth_hash.info.team_name

    user      = User.find_or_create_from_openid!(auth_hash)
    workspace = Workspace.find_by(platform: :slack, platform_id: team_id)

    return AuthOutcome.install_needed(user: user, team_id: team_id, team_name: team_name) if workspace.nil?

    membership = workspace.workspace_memberships.find_by(user: user)
    return AuthOutcome.signed_in(membership: membership, message: "Welcome back to Firefight.") if membership

    if (invitation = active_invitation_for(pending_invitation_id, workspace, email))
      membership = invitation.consume!(user: user, auth_hash: auth_hash)
      return AuthOutcome.signed_in(membership: membership, message: "You're in. Welcome to #{workspace.name}.")
    end

    if workspace.allow_auto_provision?
      membership = workspace.auto_provision_member!(user: user, auth_hash: auth_hash)
      return AuthOutcome.signed_in(membership: membership, message: "Welcome to #{workspace.name}.")
    end

    AuthOutcome.invite_needed(team_name: team_name)
  end

  # Bot install callback. Wraps the existing workspace install flow and returns
  # an AuthOutcome so the controller has a uniform interface.
  def handle_install(auth_hash)
    result = Workspace.process_slack_installation(auth_hash)

    trigger_workspace_setup(result[:workspace], auth_hash.uid) if result[:first_install]

    message = result[:first_install] ? "Setting up your Firefight workspace..." : "Signed in."
    AuthOutcome.signed_in(
      membership: result[:membership],
      message: message,
      first_install: result[:first_install]
    )
  end

  # Kept for backward compatibility — older callers still expect a Hash.
  def process_oauth_callback(auth_hash)
    result = Workspace.process_slack_installation(auth_hash)
    trigger_workspace_setup(result[:workspace], auth_hash.uid) if result[:first_install]
    result
  end

  private

  def active_invitation_for(id, workspace, email)
    return nil unless id
    invite = Invitation.active.find_by(id: id, workspace: workspace)
    invite if invite&.email&.casecmp?(email)
  end

  def trigger_workspace_setup(workspace, installer_user_id)
    Rails.logger.info({
      event: "slack_authentication.workspace_setup_triggered",
      workspace_id: workspace.id,
      installer_user_id: installer_user_id
    })

    SlackWorkspaceSetupWorkflow.start!(
      workspace,
      context: { installer_user_id: installer_user_id }
    )
  end
end
