# Decides what the controller does next after a Slack auth callback. HTTP stays
# in the controller, state changes on the models.
class SlackAuthenticationService
  INVITE_REQUIRED_MESSAGE   = "Public beta access currently requires an invite code.".freeze
  WORKSPACE_MISMATCH_MESSAGE = "Workspace mismatch. Please sign in again with the workspace you want to connect.".freeze
  TEAM_TAKEN_MESSAGE = "This Slack workspace is already connected to another Firefight workspace. Sign in with Slack to join it, or ask its admin to invite you.".freeze
  CONNECT_FAILED_MESSAGE = "Only an admin of the Firefight workspace can connect Slack to it.".freeze
  ALREADY_CONNECTED_MESSAGE = "This Firefight workspace is already connected to Slack.".freeze
  CONNECTED_MESSAGE = "Slack is connected. Firefight is setting up your incidents channel.".freeze
  UNVERIFIED_EMAIL_MESSAGE = "Slack has not verified the email on your account. Verify it in Slack, then sign in again.".freeze

  # A Slack user id is only unique inside its team, so the team is part of the identity.
  def self.identity_uid(team_id, user_id) = "#{team_id}/#{user_id}"

  # Invite gating applies only to new workspace installs and only when
  # InviteCode.required? is true. Members of an existing workspace always auto-provision.
  def handle_openid_signin(auth_hash)
    team_id   = auth_hash.info.team_id
    team_name = auth_hash.info.team_name

    result = AuthenticationService.new.sign_in_with(claims_from(auth_hash), create_user: true, refresh_profile: true)
    return AuthOutcome.refused(message: UNVERIFIED_EMAIL_MESSAGE) if result.unverified_email?

    user      = result.user
    workspace = Workspace.find_by(platform: :slack, platform_id: team_id)

    return AuthOutcome.install_needed(user: user, team_id: team_id, team_name: team_name) if workspace.nil?

    membership = workspace.workspace_memberships.find_by(user: user)
    return AuthOutcome.signed_in(membership: membership.link_platform_user!(auth_hash.uid)) if membership

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
  # connecting is a workspace that started without Slack and is being connected by one of its admins. reused says it was
  # not just named but carried on from an earlier signup (SignInSession#continue_in_unconnected), so connecting it is news.
  def handle_install(auth_hash, user: nil, invite_code: nil, pending_team_id: nil, connecting: nil, reused: false)
    team_id = auth_hash.extra.team_info["id"]

    if pending_team_id.present? && pending_team_id != team_id
      Rails.logger.warn({
        event: "slack_authentication.team_mismatch",
        pending_team_id: pending_team_id,
        install_team_id: team_id
      })
      return AuthOutcome.invite_required(message: WORKSPACE_MISMATCH_MESSAGE)
    end

    return connect(auth_hash, connecting, user, signed_up_with_team: pending_team_id.present? && !reused) if connecting

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

    trigger_workspace_setup(result[:workspace], auth_hash.uid) if result[:first_install]
    if result[:created]
      SignupNotificationService.announce(SignupNotificationService::WORKSPACE_CREATED, result[:workspace], result[:membership],
                                         sign_up_method: UserIdentity::SLACK)
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

  # One Slack team belongs to one Firefight workspace, so a team already here is refused rather than merged.
  # signed_up_with_team is a workspace just named from a Slack sign-in in this team, already announced as created
  # with Slack, so connecting it is not announced again.
  def connect(auth_hash, workspace, user, signed_up_with_team:)
    team_id = auth_hash.extra.team_info["id"]
    membership = user && workspace.workspace_memberships.find_by(user: user)
    return AuthOutcome.refused(message: CONNECT_FAILED_MESSAGE) unless membership
    return AuthOutcome.refused(message: TEAM_TAKEN_MESSAGE) if Workspace.where.not(id: workspace.id).exists?(platform: Platforms::SLACK, platform_id: team_id)

    result = Workspace.process_slack_installation(auth_hash, user: user, workspace: workspace)
    trigger_workspace_setup(result[:workspace], auth_hash.uid)
    unless signed_up_with_team
      SignupNotificationService.announce(SignupNotificationService::CHAT_CONNECTED, result[:workspace], result[:membership])
    end
    AuthOutcome.signed_in(membership: result[:membership], message: CONNECTED_MESSAGE)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Another workspace connected the same team a moment earlier.
    AuthOutcome.refused(message: TEAM_TAKEN_MESSAGE)
  rescue Workspace::ChatConnection::AlreadyConnected
    AuthOutcome.refused(message: ALREADY_CONNECTED_MESSAGE)
  end

  def claims_from(auth_hash)
    info = auth_hash.info
    AuthenticationService::Claims.new(
      provider: UserIdentity::SLACK,
      uid: self.class.identity_uid(info.team_id, auth_hash.uid),
      email: info.email,
      email_verified: info.email_verified,
      name: info.name,
      avatar_url: info.image
    )
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
