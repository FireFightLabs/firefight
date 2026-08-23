module Slack::WorkspaceAdapter::WorkspaceSetup
  extend ActiveSupport::Concern

  # Returns :channel_id, :channel_name and :already_existed.
  def create_incidents_channel
    translate_errors do
      result = Slack::Client.create_channel(
        workspace: @workspace,
        name: "incidents",
        is_private: false
      )

      {
        channel_id: result[:channel][:id],
        channel_name: result[:channel][:name],
        already_existed: false
      }
    end
  rescue AdapterError::ChannelExists => e
    Rails.logger.warn({
      event: "slack.workspace_adapter.channel_already_exists",
      message: "Incidents channel already exists, will use existing",
      workspace_id: @workspace.id,
      error: e.message
    })

    existing = find_existing_channel("incidents")

    {
      channel_id: existing[:id],
      channel_name: existing[:name],
      already_existed: true
    }
  end

  def post_welcome_message(channel_id:)
    translate_errors do
      message = Slack::InstallationMessageBuilder.welcome_message_blocks

      result = Slack::Client.post_message(
        workspace: @workspace,
        channel: channel_id,
        text: "Welcome to FireFight!",
        blocks: message[:blocks]
      )

      { message_id: result[:ts], channel_id: result[:channel] }
    end
  end

  def post_preview_announcement(channel_id:, user_id:)
    translate_errors do
      preview = Slack::InstallationMessageBuilder.preview_announcement_blocks(user_id)

      result = Slack::Client.post_ephemeral(
        workspace: @workspace,
        channel: channel_id,
        user: user_id,
        text: "[PREVIEW] Website is down",
        blocks: preview[:blocks]
      )

      { success: true }
    end
  end

  def open_share_modal(trigger_id:, user_id:, channel_id:)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::InstallationMessageBuilder.share_channel_modal(user_id, channel_id)
    )
  end

  # Returns :shared_count and :failed_count, since a share can partly fail.
  def post_share_messages(user_id:, channel_id:, target_conversations:)
    share_message = Slack::InstallationMessageBuilder.share_message(
      user_id,
      channel_id,
      @workspace.platform_id
    )

    succeeded = 0
    failed = 0

    target_conversations.each do |conversation_id|
      begin
        translate_errors do
          Slack::Client.post_message(
            workspace: @workspace,
            channel: conversation_id,
            text: "FireFight is available in this workspace",
            blocks: share_message[:blocks]
          )
        end
        succeeded += 1
      rescue AdapterError => e
        Rails.logger.warn({
          event: "slack.workspace_adapter.share_failed",
          message: "Failed to share to conversation",
          workspace_id: @workspace.id,
          conversation_id: conversation_id,
          error: e.message
        })
        failed += 1
      end
    end

    { shared_count: succeeded, failed_count: failed }
  end

  private

  def find_existing_channel(name)
    translate_errors do
      channels = Slack::Client.list_conversations(workspace: @workspace)
      channel = channels.find { |ch| ch[:name] == name }

      raise Slack::Client::ChannelNotFoundError, "Channel '#{name}' not found" unless channel

      channel
    end
  end
end
