
module Slack
  class WorkspaceAdapter
    CHANNEL_DESCRIPTION = "FireFight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date."

    def initialize(workspace)
      @workspace = workspace
    end

    # Create a Slack channel with given name
    #
    # @param name [String] Channel name
    # @param is_private [Boolean] Whether channel is private
    # @return [Hash] { channel_id:, channel_name: }
    def create_channel(name:, is_private: false)
      result = Slack::Client.create_channel(
        workspace: @workspace,
        name: name,
        is_private: is_private
      )

      {
        channel_id: result[:channel][:id],
        channel_name: result[:channel][:name]
      }
    rescue Slack::Client::ChannelExistsError
      raise AdapterError::ChannelExists, "Channel name already taken"
    end

    # Create incidents channel
    #
    # @return [Hash] Normalized response with :channel_id, :channel_name, :already_existed
    def create_incidents_channel
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
    rescue Slack::Client::ChannelExistsError => e
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

    def archive_channel(channel_id:)
      Slack::Client.archive_channel(workspace: @workspace, channel: channel_id)
      { success: true }
    rescue Slack::Client::AlreadyArchivedError
      raise AdapterError::AlreadyArchived, "Channel is already archived"
    end

    def set_channel_topic(channel_id:, topic:)
      Slack::Client.set_channel_topic(
        workspace: @workspace,
        channel: channel_id,
        topic: topic
      )

      { success: true }
    end

    def set_channel_metadata(channel_id:, topic:, purpose:)
      Slack::Client.set_channel_topic(
        workspace: @workspace,
        channel: channel_id,
        topic: topic
      )

      Slack::Client.set_channel_purpose(
        workspace: @workspace,
        channel: channel_id,
        purpose: purpose
      )

      { success: true }
    end

    def post_message(channel_id:, text:, blocks:)
      result = Slack::Client.post_message(
        workspace: @workspace,
        channel: channel_id,
        text: text,
        blocks: blocks
      )

      { message_ts: result[:ts] }
    end

    def pin_message(channel_id:, timestamp:)
      Slack::Client.pin_message(
        workspace: @workspace,
        channel: channel_id,
        timestamp: timestamp
      )

      { ok: true }
    end

    def invite_user(channel_id:, user_id:)
      Slack::Client.invite_to_channel(
        workspace: @workspace,
        channel: channel_id,
        users: user_id
      )

      { invited_user: user_id }
    end

    def post_welcome_message(channel_id:)
      message = Slack::InstallationMessageBuilder.welcome_message_blocks

      result = Slack::Client.post_message(
        workspace: @workspace,
        channel: channel_id,
        text: "Welcome to FireFight!",
        blocks: message[:blocks]
      )

      { message_ts: result[:ts] }
    end

    # Post preview announcement (ephemeral - only visible to user)
    #
    # @param channel_id [String] Slack channel ID
    # @param user_id [String] Slack user ID who will see the preview
    # @return [Hash] Response with :message_ts
    def post_preview_announcement(channel_id:, user_id:)
      preview = Slack::InstallationMessageBuilder.preview_announcement_blocks(user_id)

      result = Slack::Client.post_ephemeral(
        workspace: @workspace,
        channel: channel_id,
        user: user_id,
        text: "[PREVIEW] Website is down",
        blocks: preview[:blocks]
      )

      { message_ts: result[:ts] }
    end

    def open_modal(trigger_id:, view:)
      Slack::Client.open_modal(
        workspace: @workspace,
        trigger_id: trigger_id,
        view: view
      )

      { success: true }
    rescue Slack::Client::TriggerExpiredError
      raise AdapterError::TriggerExpired, "Modal trigger expired"
    end

    def push_modal(trigger_id:, view:)
      Slack::Client.push_modal(
        workspace: @workspace,
        trigger_id: trigger_id,
        view: view
      )

      { success: true }
    rescue Slack::Client::TriggerExpiredError
      raise AdapterError::TriggerExpired, "Modal trigger expired"
    end

    # Open share channel modal
    #
    # @param trigger_id [String] Slack trigger ID from interaction
    # @param user_id [String] Slack user ID who clicked the button
    # @param channel_id [String] Incidents channel ID to share
    # @return [Hash] Response with :success
    def open_share_modal(trigger_id:, user_id:, channel_id:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::InstallationMessageBuilder.share_channel_modal(user_id, channel_id)
      )
    end

    # Post share message to selected channels
    #
    # @param user_id [String] User ID who is sharing
    # @param channel_id [String] Incidents channel ID
    # @param target_conversations [Array<String>] Channel/DM IDs to post to
    # @return [Hash] Response with :shared_count, :failed_count
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
          Slack::Client.post_message(
            workspace: @workspace,
            channel: conversation_id,
            text: "FireFight is available in this workspace",
            blocks: share_message[:blocks]
          )
          succeeded += 1
        rescue Slack::Client::ApiError => e
          # Handle errors gracefully (bot not in channel, missing permissions, etc.)
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

    def open_incident_creation_modal(trigger_id:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.incident_creation_form
      )
    end

    def open_home_modal(trigger_id:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.home_modal
      )
    end

    def update_home_modal(view:, selected_command:)
      help_text = Slack::ModalBuilder.home_command_help(selected_command)

      updated_blocks = view["blocks"].map do |block|
        if block["block_id"] == "command_details_block"
          block.merge("text" => { "type" => "mrkdwn", "text" => help_text })
        else
          block
        end
      end

      Slack::Client.update_modal(
        workspace: @workspace,
        view_id: view["id"],
        view: {
          type: "modal",
          callback_id: Identifiers::INCIDENT_HOME_MODAL,
          title: view["title"],
          close: view["close"],
          blocks: updated_blocks
        }
      )

      { success: true }
    end

    def update_message(channel_id:, ts:, text:, blocks:)
      Slack::Client.update_message(
        workspace: @workspace,
        channel: channel_id,
        ts: ts,
        text: text,
        blocks: blocks
      )

      { success: true }
    end

    def update_incident_quick_actions(channel_id:, ts:, incident:)
      blocks = Slack::IncidentMessageBuilder.quick_actions_blocks(incident)
      update_message(
        channel_id: channel_id,
        ts: ts,
        text: "#{incident.identifier} - Quick Actions",
        blocks: blocks
      )
    end

    def update_incident_announcement(channel_id:, ts:, incident:)
      blocks = Slack::IncidentMessageBuilder.announcement_blocks(incident)
      update_message(
        channel_id: channel_id,
        ts: ts,
        text: "New incident: #{incident.identifier}",
        blocks: blocks
      )
    end

    def delete_message(channel_id:, ts:)
      Slack::Client.delete_message(
        workspace: @workspace,
        channel: channel_id,
        ts: ts
      )

      { success: true }
    end

    def open_summary_modal(trigger_id:, incident:, private_metadata: nil)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.summary_modal(incident, private_metadata: private_metadata)
      )
    end

    def open_lead_modal(trigger_id:, incident:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.lead_modal(incident)
      )
    end

    def post_lead_expectations(channel_id:, user_id:)
      text = "*You're now the Incident Lead.* Here's what's expected:\n" \
             "- Make sure it's clear who is doing what\n" \
             "- Ensure everybody has what they need\n" \
             "- Provide regular, clear updates"
      post_ephemeral(channel_id: channel_id, user_id: user_id, text: text)
    end

    def post_incident_quick_actions(channel_id:, incident:)
      blocks = Slack::IncidentMessageBuilder.quick_actions_blocks(incident)
      post_message(
        channel_id: channel_id,
        text: "#{incident.identifier} - Quick Actions",
        blocks: blocks
      )
    end

    def post_incident_announcement(channel_id:, incident:)
      blocks = Slack::IncidentMessageBuilder.announcement_blocks(incident)
      post_message(
        channel_id: channel_id,
        text: "New incident: #{incident.identifier}",
        blocks: blocks
      )
    end

    def open_incident_update_modal(trigger_id:, incident:, private_metadata: nil)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.incident_update_modal(incident, private_metadata: private_metadata)
      )
    end

    def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil)
      blocks = Slack::IncidentMessageBuilder.status_update_blocks(
        incident,
        message: message,
        updated_by_platform_user_id: updated_by_platform_user_id,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name
      )
      post_message(channel_id: channel_id, text: "Incident updated", blocks: blocks)
    end

    def post_incident_update_announcement_thread(channel_id:, thread_ts:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil)
      blocks = Slack::IncidentMessageBuilder.status_update_announcement_blocks(
        incident,
        message: message,
        updated_by_platform_user_id: updated_by_platform_user_id,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name
      )
      post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident updated", blocks: blocks)
    end

    def post_incident_update_reminder(channel_id:, user_id:, incident:)
      blocks = Slack::IncidentMessageBuilder.update_reminder_blocks(incident)
      post_ephemeral(
        channel_id: channel_id,
        user_id: user_id,
        text: "It's time to provide a status update for #{incident.identifier}",
        blocks: blocks
      )
    end

    def open_actions_list_modal(trigger_id:, incident:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.actions_list_modal(incident)
      )
    end

    def open_followups_list_modal(trigger_id:, incident:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.followups_list_modal(incident)
      )
    end

    def open_create_action_modal(trigger_id:, incident:, private_metadata: nil, push: false)
      view = Slack::ModalBuilder.create_action_modal(incident, private_metadata: private_metadata)
      push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
    end

    def open_create_followup_modal(trigger_id:, incident:, private_metadata: nil, push: false)
      view = Slack::ModalBuilder.create_followup_modal(incident, private_metadata: private_metadata)
      push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
    end

    def post_action_message(channel_id:, action:)
      type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
      blocks = Slack::IncidentMessageBuilder.action_created_blocks(action)
      post_message(channel_id: channel_id, text: "New #{type_label} added", blocks: blocks)
    end

    def update_action_message(channel_id:, ts:, action:, blocks:)
      type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
      update_message(channel_id: channel_id, ts: ts, text: "#{type_label.capitalize} updated", blocks: blocks)
    end

    def get_message_permalink(channel_id:, message_ts:)
      result = Slack::Client.get_permalink(
        workspace: @workspace,
        channel: channel_id,
        message_ts: message_ts
      )

      { permalink: result[:permalink] }
    end

    def fetch_message(channel_id:, ts:)
      Slack::Client.get_message(
        workspace: @workspace,
        channel: channel_id,
        ts: ts
      )
    end

    def post_action_from_reaction_prompt(channel_id:, user_id:, action_type:, message_text:, incident_id:, source_message_link:)
      blocks = Slack::IncidentMessageBuilder.action_from_reaction_blocks(
        action_type, message_text, incident_id, source_message_link
      )
      type_label = action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
      post_ephemeral(
        channel_id: channel_id,
        user_id: user_id,
        text: "Create #{type_label} from this message?",
        blocks: blocks
      )
    end

    def post_threaded_message(channel_id:, thread_ts:, text:, blocks: nil)
      result = Slack::Client.post_message(
        workspace: @workspace,
        channel: channel_id,
        text: text,
        blocks: blocks,
        thread_ts: thread_ts
      )

      { message_ts: result[:ts] }
    end

    def post_ephemeral(channel_id:, user_id:, text:, blocks: nil)
      Slack::Client.post_ephemeral(
        workspace: @workspace,
        channel: channel_id,
        user: user_id,
        text: text,
        blocks: blocks
      )

      { success: true }
    end

    private

    def find_existing_channel(name)
      channels = Slack::Client.list_conversations(workspace: @workspace)
      channel = channels.find { |ch| ch[:name] == name }

      raise Slack::Client::ChannelNotFoundError, "Channel '#{name}' not found" unless channel

      channel
    end
  end
end
