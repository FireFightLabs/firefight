
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
      translate_errors do
        result = Slack::Client.create_channel(
          workspace: @workspace,
          name: name,
          is_private: is_private
        )

        {
          channel_id: result[:channel][:id],
          channel_name: result[:channel][:name]
        }
      end
    end

    # Create incidents channel
    #
    # @return [Hash] Normalized response with :channel_id, :channel_name, :already_existed
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

    def archive_channel(channel_id:)
      translate_errors do
        Slack::Client.archive_channel(workspace: @workspace, channel: channel_id)
        { success: true }
      end
    end

    def set_channel_topic(channel_id:, topic:)
      translate_errors do
        Slack::Client.set_channel_topic(
          workspace: @workspace,
          channel: channel_id,
          topic: topic
        )

        { success: true }
      end
    end

    def set_channel_metadata(channel_id:, topic:, purpose:)
      translate_errors do
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
    end

    def post_message(channel_id:, text:, blocks:)
      translate_errors do
        result = Slack::Client.post_message(
          workspace: @workspace,
          channel: channel_id,
          text: text,
          blocks: blocks
        )

        { message_ts: result[:ts] }
      end
    end

    def pin_message(channel_id:, timestamp:)
      translate_errors do
        Slack::Client.pin_message(
          workspace: @workspace,
          channel: channel_id,
          timestamp: timestamp
        )

        { ok: true }
      end
    end

    def invite_user(channel_id:, user_id:)
      translate_errors do
        Slack::Client.invite_to_channel(
          workspace: @workspace,
          channel: channel_id,
          users: user_id
        )

        { invited_user: user_id }
      end
    end

    def invite_users(channel_id:, user_ids:)
      translate_errors do
        Slack::Client.invite_to_channel(
          workspace: @workspace,
          channel: channel_id,
          users: user_ids
        )

        { invited_users: user_ids }
      end
    end

    def resolve_user_ids_from_handles(handles:)
      normalized_handles = Array(handles).map { |handle| normalize_handle(handle) }.reject(&:blank?).uniq
      return { resolved_user_ids: [], unresolved_handles: [] } if normalized_handles.empty?

      alias_to_user_id = {}
      Slack::Client.list_users(workspace: @workspace).each do |member|
        next if member[:deleted]
        next if member[:is_bot]

        user_id = member[:id].to_s
        next if user_id.blank?

        aliases_for_member(member).each do |handle_alias|
          alias_to_user_id[handle_alias] ||= user_id
        end
      end

      resolved = []
      unresolved = []
      normalized_handles.each do |handle|
        user_id = alias_to_user_id[handle]
        if user_id
          resolved << user_id
        else
          unresolved << handle
        end
      end

      { resolved_user_ids: resolved.uniq, unresolved_handles: unresolved }
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

        { message_ts: result[:ts] }
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

        { message_ts: result[:ts] }
      end
    end

    def open_modal(trigger_id:, view:)
      translate_errors do
        Slack::Client.open_modal(
          workspace: @workspace,
          trigger_id: trigger_id,
          view: view
        )

        { success: true }
      end
    end

    def push_modal(trigger_id:, view:)
      translate_errors do
        Slack::Client.push_modal(
          workspace: @workspace,
          trigger_id: trigger_id,
          view: view
        )

        { success: true }
      end
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
      translate_errors do
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
    end

    def update_message(channel_id:, ts:, text:, blocks:)
      translate_errors do
        Slack::Client.update_message(
          workspace: @workspace,
          channel: channel_id,
          ts: ts,
          text: text,
          blocks: blocks
        )

        { success: true }
      end
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
      translate_errors do
        Slack::Client.delete_message(
          workspace: @workspace,
          channel: channel_id,
          ts: ts
        )

        { success: true }
      end
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

    def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
      blocks = Slack::IncidentMessageBuilder.status_update_blocks(
        incident,
        message: message,
        updated_by_platform_user_id: updated_by_platform_user_id,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name,
        previous_type_name: previous_type_name
      )
      post_message(channel_id: channel_id, text: "Incident updated", blocks: blocks)
    end

    def post_incident_update_announcement_thread(channel_id:, thread_ts:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
      blocks = Slack::IncidentMessageBuilder.status_update_announcement_blocks(
        incident,
        message: message,
        updated_by_platform_user_id: updated_by_platform_user_id,
        previous_status_name: previous_status_name,
        previous_severity_name: previous_severity_name,
        previous_type_name: previous_type_name
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

    def open_close_incident_modal(trigger_id:, incident:, private_metadata: nil)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.close_modal(incident, private_metadata: private_metadata)
      )
    end

    def open_link_incident_modal(trigger_id:, incident:, private_metadata: nil)
      view = Slack::ModalBuilder.link_incident_modal(incident, private_metadata: private_metadata)
      return unless view

      open_modal(trigger_id: trigger_id, view: view)
    end

    def open_reopen_incident_modal(trigger_id:, incident:, private_metadata: nil)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.reopen_modal(incident, private_metadata: private_metadata)
      )
    end

    def open_escalate_incident_modal(trigger_id:, incident:, private_metadata: nil)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.escalate_modal(incident, private_metadata: private_metadata)
      )
    end

    def open_invite_responders_modal(trigger_id:, incident:, selected_user_ids: [], private_metadata: nil)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.invite_responders_modal(
          incident,
          selected_user_ids: selected_user_ids,
          private_metadata: private_metadata
        )
      )
    end

    def post_resolution_message(channel_id:, incident:, resolved_by_platform_user_id:)
      blocks = Slack::IncidentMessageBuilder.resolution_blocks(incident, resolved_by_platform_user_id: resolved_by_platform_user_id)
      post_message(channel_id: channel_id, text: "Incident resolved", blocks: blocks)
    end

    def post_resolution_announcement_thread(channel_id:, thread_ts:, incident:, resolved_by_platform_user_id:)
      blocks = Slack::IncidentMessageBuilder.resolution_announcement_thread_blocks(incident, resolved_by_platform_user_id: resolved_by_platform_user_id)
      post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident resolved", blocks: blocks)
    end

    def post_related_link_message(channel_id:, source:, target:, linked_by_platform_user_id:)
      blocks = Slack::IncidentMessageBuilder.related_link_blocks(source, target, linked_by_platform_user_id: linked_by_platform_user_id)
      post_message(channel_id: channel_id, text: "Incident linked", blocks: blocks)
    end

    def post_duplicate_source_message(channel_id:, source:, canonical:, linked_by_platform_user_id:)
      blocks = Slack::IncidentMessageBuilder.duplicate_source_blocks(source, canonical, linked_by_platform_user_id: linked_by_platform_user_id)
      post_message(channel_id: channel_id, text: "Incident merged", blocks: blocks)
    end

    def post_duplicate_canonical_message(channel_id:, source:, canonical:, linked_by_platform_user_id:)
      blocks = Slack::IncidentMessageBuilder.duplicate_canonical_blocks(source, canonical, linked_by_platform_user_id: linked_by_platform_user_id)
      post_message(channel_id: channel_id, text: "Duplicate merged in", blocks: blocks)
    end

    def post_reopen_message(channel_id:, incident:, reopened_by_platform_user_id:, reason: nil)
      blocks = Slack::IncidentMessageBuilder.reopen_blocks(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reason: reason)
      post_message(channel_id: channel_id, text: "Incident reopened", blocks: blocks)
    end

    def post_reopen_announcement_thread(channel_id:, thread_ts:, incident:, reopened_by_platform_user_id:, reason: nil)
      blocks = Slack::IncidentMessageBuilder.reopen_announcement_thread_blocks(incident, reopened_by_platform_user_id: reopened_by_platform_user_id, reason: reason)
      post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident reopened", blocks: blocks)
    end

    def post_escalation_message(channel_id:, incident:, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
      blocks = Slack::IncidentMessageBuilder.escalation_blocks(
        incident,
        escalated_by_platform_user_id: escalated_by_platform_user_id,
        escalated_to_platform_user_id: escalated_to_platform_user_id,
        reason: reason
      )
      post_message(channel_id: channel_id, text: "Incident escalated", blocks: blocks)
    end

    def post_escalation_announcement_thread(channel_id:, thread_ts:, incident:, escalated_by_platform_user_id:, escalated_to_platform_user_id:, reason: nil)
      blocks = Slack::IncidentMessageBuilder.escalation_announcement_thread_blocks(
        incident,
        escalated_by_platform_user_id: escalated_by_platform_user_id,
        escalated_to_platform_user_id: escalated_to_platform_user_id,
        reason: reason
      )
      post_threaded_message(channel_id: channel_id, thread_ts: thread_ts, text: "Incident escalated", blocks: blocks)
    end

    def post_escalation_direct_message(user_id:, incident:, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
      blocks = Slack::IncidentMessageBuilder.escalation_direct_message_blocks(
        incident,
        escalated_by_platform_user_id: escalated_by_platform_user_id,
        escalation_event_id: escalation_event_id,
        reason: reason
      )
      post_message(channel_id: user_id, text: "Incident escalated to you", blocks: blocks)
    end

    def post_escalation_acknowledged_message(channel_id:, incident:, acknowledged_by_platform_user_id:, escalated_to_platform_user_id:)
      blocks = Slack::IncidentMessageBuilder.escalation_acknowledged_blocks(
        incident,
        acknowledged_by_platform_user_id: acknowledged_by_platform_user_id,
        escalated_to_platform_user_id: escalated_to_platform_user_id
      )
      post_message(channel_id: channel_id, text: "Escalation acknowledged", blocks: blocks)
    end

    def post_escalation_nudge_direct_message(user_id:, incident:, escalated_by_platform_user_id:, escalation_event_id:, reason: nil)
      blocks = Slack::IncidentMessageBuilder.escalation_nudge_direct_message_blocks(
        incident,
        escalated_by_platform_user_id: escalated_by_platform_user_id,
        escalation_event_id: escalation_event_id,
        reason: reason
      )
      post_message(channel_id: user_id, text: "Reminder to acknowledge escalation", blocks: blocks)
    end

    def post_action_message(channel_id:, action:)
      type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
      blocks = Slack::IncidentMessageBuilder.action_created_blocks(action)
      post_message(channel_id: channel_id, text: "New #{type_label} added", blocks: blocks)
    end

    def update_action_picked_up(channel_id:, ts:, action:)
      blocks = Slack::IncidentMessageBuilder.action_picked_up_blocks(action)
      type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
      update_message(channel_id: channel_id, ts: ts, text: "#{type_label.capitalize} updated", blocks: blocks)
    end

    def update_action_completed(channel_id:, ts:, action:)
      blocks = Slack::IncidentMessageBuilder.action_completed_blocks(action)
      type_label = action.action_type == IncidentAction::ACTION_TYPE_FOLLOWUP ? "follow-up" : "action"
      update_message(channel_id: channel_id, ts: ts, text: "#{type_label.capitalize} updated", blocks: blocks)
    end

    def get_message_permalink(channel_id:, message_ts:)
      translate_errors do
        result = Slack::Client.get_permalink(
          workspace: @workspace,
          channel: channel_id,
          message_ts: message_ts
        )

        { permalink: result[:permalink] }
      end
    end

    def fetch_message(channel_id:, ts:)
      translate_errors do
        Slack::Client.get_message(
          workspace: @workspace,
          channel: channel_id,
          ts: ts
        )
      end
    end

    def archive_slack_file(incident_event:, slack_file:)
      download_url = slack_file["url_private_download"] || slack_file["url_private"]
      return { archived: false } if download_url.blank?

      translate_errors do
        payload = Slack::Client.download_file(workspace: @workspace, url: download_url)
        filename = slack_file["name"].presence || "incident-file"
        content_type = slack_file["mimetype"].presence || payload[:content_type]

        incident_event.artifact.attach(
          io: StringIO.new(payload[:body]),
          filename: filename,
          content_type: content_type
        )

        blob = incident_event.artifact.blob

        {
          archived: true,
          object_key: blob.key,
          blob_id: blob.id,
          byte_size: blob.byte_size,
          checksum: blob.checksum
        }
      end
    end


    def get_user_info(user_id:)
      translate_errors do
        Slack::Client.get_user_info(workspace: @workspace, user_id: user_id)
      end
    end

    def open_shoutout_modal(trigger_id:, incident:)
      open_modal(
        trigger_id: trigger_id,
        view: Slack::ModalBuilder.shoutout_modal(incident)
      )
    end

    def post_shoutout_message(channel_id:, incident:, from_user_id:, recipient_user_id:, message:)
      blocks = Slack::IncidentMessageBuilder.shoutout_blocks(
        incident,
        from_user_id: from_user_id,
        recipient_user_id: recipient_user_id,
        message: message
      )
      post_message(channel_id: channel_id, text: ":heart_on_fire: Shoutout in #{incident.identifier}", blocks: blocks)
    end

    def post_shoutout_from_reaction_prompt(channel_id:, user_id:, incident_id:)
      blocks = Slack::IncidentMessageBuilder.shoutout_from_reaction_blocks(incident_id)
      post_ephemeral(
        channel_id: channel_id,
        user_id: user_id,
        text: "Give a shoutout?",
        blocks: blocks
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
      translate_errors do
        result = Slack::Client.post_message(
          workspace: @workspace,
          channel: channel_id,
          text: text,
          blocks: blocks,
          thread_ts: thread_ts
        )

        { message_ts: result[:ts] }
      end
    end

    def post_ephemeral(channel_id:, user_id:, text:, blocks: nil)
      translate_errors do
        Slack::Client.post_ephemeral(
          workspace: @workspace,
          channel: channel_id,
          user: user_id,
          text: text,
          blocks: blocks
        )

        { success: true }
      end
    end

    private

    def normalize_handle(handle)
      handle.to_s.downcase.strip.delete_prefix("@")
    end

    def aliases_for_member(member)
      profile = member[:profile] || {}
      aliases = []

      aliases << normalize_handle(member[:name])
      aliases << normalize_handle(profile[:display_name])
      aliases << normalize_handle(profile[:display_name_normalized])
      aliases << normalize_handle(profile[:real_name])
      aliases << normalize_handle(profile[:real_name_normalized])

      email_local = profile[:email].to_s.split("@").first
      aliases << normalize_handle(email_local)

      aliases.compact.reject(&:blank?).uniq
    end

    def translate_errors
      yield
    rescue Slack::Client::TriggerExpiredError
      raise AdapterError::TriggerExpired, "Modal trigger expired"
    rescue Slack::Client::ChannelExistsError
      raise AdapterError::ChannelExists, "Channel name already taken"
    rescue Slack::Client::AlreadyArchivedError
      raise AdapterError::AlreadyArchived, "Channel is already archived"
    rescue Slack::Client::ChannelNotFoundError
      raise AdapterError::NotFound, "Channel not found"
    rescue Slack::Client::ApiError => e
      raise AdapterError, e.message
    end

    def find_existing_channel(name)
      translate_errors do
        channels = Slack::Client.list_conversations(workspace: @workspace)
        channel = channels.find { |ch| ch[:name] == name }

        raise Slack::Client::ChannelNotFoundError, "Channel '#{name}' not found" unless channel

        channel
      end
    end
  end
end
