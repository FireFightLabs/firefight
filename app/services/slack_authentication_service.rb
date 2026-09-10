# Decides what the controller does next after a Slack auth callback. HTTP stays
# in the controller, state changes on the models.
class SlackAuthenticationService
  INVITE_REQUIRED_MESSAGE   = "Public beta access currently requires an invite code.".freeze
  WORKSPACE_MISMATCH_MESSAGE = "Workspace mismatch. Please sign in again with the workspace you want to connect.".freeze

  # Invite gating applies only to new workspace installs and only when
  # InviteCode.required? is true. Members of an existing workspace always auto-provision.
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

  # user comes from the prior OIDC sign-in, never the install auth_hash. pending_team_id must
  # match the auth_hash team, or someone could sign in to team A and install into team B past the invite gate.
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

    if existing_workspace.nil? && InviteCode.required? && !invite_code&.active?
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
      invite_code.redeem!(user) if existing_workspace.nil? && InviteCode.required?
      Workspace.process_slack_installation(auth_hash, user: user)
    end

    if result[:first_install]
      trigger_workspace_setup(result[:workspace], auth_hash.uid)
      notify_install(result[:workspace], result[:membership])
    end

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

  def notify_install(workspace, membership)
    return unless InstallNotificationService.configured?

    InstallNotificationJob.perform_later(workspace.id, membership.id)
  end
end
