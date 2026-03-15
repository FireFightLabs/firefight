# Service for workspace setup operations
# Provides reusable business logic for setting up workspaces across different platforms
#
# Can be called from:
# - Workflows (orchestrated setup)
# - Controllers (manual admin actions)
# - Console (debugging/testing)
# - API endpoints (future)
class WorkspaceSetupService
  INCIDENTS_CHANNEL_DESCRIPTION = "FireFight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date."

  def initialize(workspace)
    @workspace = workspace
  end

  # Create incidents channel for a workspace
  #
  # @param workspace [Workspace] The workspace to create channel in
  # @return [Hash] Result with :channel_id, :channel_name, :already_existed
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

  # Set channel metadata (topic and description)
  #
  # @param workspace [Workspace] The workspace
  # @param channel_id [String] Channel ID
  # @return [Hash] Result with :success
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

  # Invite user to incidents channel
  #
  # @param workspace [Workspace] The workspace
  # @param channel_id [String] Channel ID
  # @param user_id [String] Platform-specific user ID
  # @param skip_if_channel_existed [Boolean] Skip if channel already existed
  # @return [Hash] Result with :invited_user or :skipped
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
  end

  # Post welcome message to incidents channel
  #
  # @param workspace [Workspace] The workspace
  # @param channel_id [String] Channel ID
  # @return [Hash] Result with :message_ts
  def post_welcome_message(workspace, channel_id)
    result = workspace.adapter.post_welcome_message(channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.welcome_posted",
      message: "Posted welcome message to incidents channel",
      workspace_id: workspace.id,
      channel_id: channel_id,
      message_ts: result[:message_ts]
    })

    result
  end

  # Store incidents channel ID in workspace record
  #
  # @param workspace [Workspace] The workspace
  # @param channel_id [String] Channel ID to store
  # @return [Hash] Result with :workspace_id, :channel_id
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
