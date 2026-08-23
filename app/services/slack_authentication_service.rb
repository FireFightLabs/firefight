# Orchestrates Slack auth callbacks. Returns AuthOutcome describing what the
# controller should do next. Decision logic lives here. HTTP concerns stay in
# the controller. State changes happen on the models.
class SlackAuthenticationService
  INVITE_REQUIRED_MESSAGE   = "Public beta access currently requires an invite code.".freeze
  WORKSPACE_MISMATCH_MESSAGE = "Workspace mismatch. Please sign in again with the workspace you want to connect.".freeze

  # OIDC sign-in (identity only). Two outcomes (plus the install-gated third):
  #   - signed_in:      workspace exists. Return or create the membership.
  #   - install_needed: no workspace for this team yet, hand off to the
  #                     onboarding invite-code step before the install callback.
  #
  # Invite gating is scoped to new workspace installs, once a workspace is on
  # Firefight, any Slack member of that team can auto-provision. Slack is the
  # source of truth for who belongs. The platform-level invite exists only to
  # gate workspaces, not individuals.
  def handle_openid_signin(auth_hash)
    team_id   = auth_hash.info.team_id
    team_name = auth_hash.info.team_name

    user      = User.find_or_create_from_openid!(auth_hash)
    workspace = Workspace.find_by(platform: :slack, platform_id: team_id)

    return AuthOutcome.install_needed(user: user, team_id: team_id, team_name: team_name) if workspace.nil?

    membership = workspace.workspace_memberships.find_by(user: user)
    return AuthOutcome.signed_in(membership: membership) if membership

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
  #   sign-in. Required for first-install. We never derive identity from the
  #   install auth_hash's user_info (brittle and not the user who signed in).
  # @param pending_team_id [String, nil] The Slack team_id captured during the
  #   prior OIDC step. If provided and does not match the auth_hash's team_id,
  #   the install is rejected, prevents bypassing invite gating by signing in
  #   for team A and redirecting the bot install to team B.
  def handle_install(auth_hash, user: nil, invite_code: nil, pending_team_id: nil)
    team_id = auth_hash.extra.team_info["id"]

    if pending_team_id.present? && pending_team_id != team_id
      Rails.logger.warn({
        event: "slack_authentication.team_mismatch",
        pending_team_id: pending_team_id,
        install_team_id: team_id
      })
      return AuthOutcome.invite_required(message: WORKSPACE_MISMATCH_MESSAGE)
    end

    existing_workspace = Workspace.find_by(platform: :slack, platform_id: team_id)

    if existing_workspace.nil? && !invite_code&.active?
      return AuthOutcome.invite_required(message: INVITE_REQUIRED_MESSAGE)
    end

    if existing_workspace.nil? && user.nil?
      Rails.logger.warn({
        event: "slack_authentication.missing_installer",
        install_team_id: team_id
      })
      return AuthOutcome.invite_required(message: INVITE_REQUIRED_MESSAGE)
    end

    result = ActiveRecord::Base.transaction do
      invite_code.redeem!(user) if existing_workspace.nil?
      Workspace.process_slack_installation(auth_hash, user: user)
    end

    trigger_workspace_setup(result[:workspace], auth_hash.uid) if result[:first_install]

    message = result[:first_install] ? "Setting up your Firefight workspace..." : "Signed in."
    AuthOutcome.signed_in(
      membership: result[:membership],
      message: message,
      first_install: result[:first_install]
    )
  rescue InviteCode::RedemptionError
    AuthOutcome.invite_required(message: INVITE_REQUIRED_MESSAGE)
  end

  # Kept for backward compatibility, older callers still expect a Hash.
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
