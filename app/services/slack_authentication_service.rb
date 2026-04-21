# Orchestrates Slack auth callbacks. Returns AuthOutcome describing what the
# controller should do next. Decision logic lives here; HTTP concerns stay in
# the controller; state changes happen on the models.
class SlackAuthenticationService
  # OIDC sign-in (identity only). Two outcomes:
  #   - install_needed: no workspace for this team yet, kick off install.
  #   - signed_in:      workspace exists; return or create the membership.
  #
  # Provisioning is always allowed for existing workspaces — Slack is the source
  # of truth. Installation is the admin gate; anyone who uses Firefight in a
  # workspace that has it installed gets a membership.
  def handle_openid_signin(auth_hash)
    team_id   = auth_hash.info.team_id
    team_name = auth_hash.info.team_name

    user      = User.find_or_create_from_openid!(auth_hash)
    workspace = Workspace.find_by(platform: :slack, platform_id: team_id)

    return AuthOutcome.install_needed(user: user, team_id: team_id, team_name: team_name) if workspace.nil?

    membership = workspace.workspace_memberships.find_by(user: user)
    return AuthOutcome.signed_in(membership: membership, message: "Welcome back to Firefight.") if membership

    membership = WorkspaceMemberProvisioner.find_or_provision!(
      workspace:        workspace,
      platform_user_id: auth_hash.uid,
      adapter:          workspace.adapter,
      user:             user,
      user_profile:     auth_hash.info
    )
    AuthOutcome.signed_in(membership: membership, message: "Welcome to #{workspace.name}.")
  end

  # Bot install callback. Wraps the existing workspace install flow and returns
  # an AuthOutcome so the controller has a uniform interface.
  #
  # @param user [User, nil] The installer, already identified by the prior OIDC
  #   sign-in. When provided, skips re-deriving identity from auth_hash.
  def handle_install(auth_hash, user: nil)
    result = Workspace.process_slack_installation(auth_hash, user: user)

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
