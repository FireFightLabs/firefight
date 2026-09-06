# The steps that stand a new workspace up, each one callable on its own so the
# setup workflow, an admin action, and the console all drive the same code.
class WorkspaceSetupService
  INCIDENTS_CHANNEL_DESCRIPTION = "FireFight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date."

  def initialize(workspace)
    @workspace = workspace
  end

  def create_incidents_channel(workspace)
    result = workspace.adapter.create_incidents_channel

    Rails.logger.info({
      event: "workspace_setup.channel_created",
      message: "Created main public incidents channel",
      workspace_id: workspace.id,
      platform: workspace.platform,
      channel_id: result[:channel_id],
      channel_name: result[:channel_name],
      already_existed: result[:already_existed]
    })

    result
  end

  def set_channel_metadata(workspace, channel_id)
    workspace.adapter.set_channel_metadata(
      channel_id: channel_id,
      topic: INCIDENTS_CHANNEL_DESCRIPTION,
      purpose: INCIDENTS_CHANNEL_DESCRIPTION
    )

    Rails.logger.info({
      event: "workspace_setup.metadata_set",
      message: "Set channel topic and description",
      workspace_id: workspace.id,
      channel_id: channel_id
    })

    { success: true }
  end

  # A channel that was already there predates this install, so its members are
  # not ours to add to.
  def invite_user(workspace, channel_id, user_id, skip_if_channel_existed: false)
    if skip_if_channel_existed
      Rails.logger.info({
        event: "workspace_setup.invite_skipped",
        message: "Skipping user invite, channel already existed",
        workspace_id: workspace.id,
        channel_id: channel_id
      })

      return { skipped: true }
    end

    workspace.adapter.invite_user(channel_id: channel_id, user_id: user_id)

    Rails.logger.info({
      event: "workspace_setup.user_invited",
      message: "Invited installer to incidents channel",
      workspace_id: workspace.id,
      channel_id: channel_id,
      user_id: user_id
    })

    { invited_user: user_id }
  rescue AdapterError::AlreadyInChannel
    { invited_user: user_id, already_in_channel: true }
  end

  # The welcome message is the onboarding checklist, so its id is kept on
  # the onboarding row for the progress updates that follow.
  def post_welcome_message(workspace, channel_id)
    onboarding = workspace.onboarding
    result = workspace.adapter.post_welcome_message(channel_id: channel_id, stage: onboarding&.stage || WorkspaceOnboarding::STAGE_NONE)
    onboarding&.update!(welcome_message_id: result[:message_id])

    Rails.logger.info({
      event: "workspace_setup.welcome_posted",
      message: "Posted welcome message to incidents channel",
      workspace_id: workspace.id,
      channel_id: channel_id,
      message_ts: result[:message_id]
    })

    result
  end

  # Redraws the checklist from the first incident's current state. Completion
  # is a fact about the incident, so it is recorded before the platform is
  # asked, and a message somebody deleted is logged and left alone.
  def refresh_welcome_message(workspace)
    onboarding = workspace.onboarding
    return { skipped: true } unless onboarding&.welcome_message_id.present? && workspace.incidents_channel_id.present?

    stage = onboarding.stage
    onboarding.complete! if stage == WorkspaceOnboarding::STAGE_DONE
    workspace.adapter.update_welcome_message(
      channel_id: workspace.incidents_channel_id,
      message_id: onboarding.welcome_message_id,
      stage: stage
    )

    { updated: true, stage: stage }
  rescue AdapterError => e
    Rails.logger.warn({
      event: "workspace_setup.welcome_refresh_failed",
      workspace_id: workspace.id,
      message_id: onboarding.welcome_message_id,
      error: e.message
    })
    { updated: false, stage: stage }
  end

  def store_channel_id(workspace, channel_id)
    workspace.update!(incidents_channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.channel_stored",
      message: "Stored incidents channel ID in workspace",
      workspace_id: workspace.id,
      channel_id: channel_id
    })

    { workspace_id: workspace.id, channel_id: channel_id }
  end
end
