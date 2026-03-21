module Slack
  class WorkspaceAdapter
    include Slack::WorkspaceAdapter::WorkspaceSetup
    include Slack::WorkspaceAdapter::UserOperations
    include Slack::WorkspaceAdapter::IncidentModals
    include Slack::WorkspaceAdapter::IncidentMessaging

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

    def archive_channel(channel_id:)
      translate_errors do
        Slack::Client.archive_channel(workspace: @workspace, channel: channel_id)
        { success: true }
      end
    end

    def unarchive_channel(channel_id:)
      translate_errors do
        Slack::Client.unarchive_channel(workspace: @workspace, channel: channel_id)
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

    def add_reaction(channel_id:, timestamp:, name:)
      translate_errors do
        Slack::Client.add_reaction(
          workspace: @workspace,
          channel: channel_id,
          timestamp: timestamp,
          name: name
        )

        { success: true }
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

    def get_user_info(user_id:)
      translate_errors do
        Slack::Client.get_user_info(workspace: @workspace, user_id: user_id)
      end
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
    rescue Slack::Client::AlreadyInChannelError
      raise AdapterError::AlreadyInChannel, "User already in channel"
    rescue Slack::Client::ApiError => e
      raise AdapterError, e.message
    end
  end
end
