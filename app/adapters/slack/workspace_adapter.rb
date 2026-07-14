module Slack
  class WorkspaceAdapter < ::PlatformAdapter
    include Slack::WorkspaceAdapter::WorkspaceSetup
    include Slack::WorkspaceAdapter::UserOperations
    include Slack::WorkspaceAdapter::IncidentModals
    include Slack::WorkspaceAdapter::IncidentMessaging

    CHANNEL_DESCRIPTION = "FireFight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date."

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

        { message_id: result[:ts], channel_id: result[:channel] }
      end
    end

    def add_reaction(channel_id:, message_id:, name:)
      translate_errors do
        Slack::Client.add_reaction(
          workspace: @workspace,
          channel: channel_id,
          timestamp: message_id,
          name: name
        )

        { success: true }
      end
    end

    def pin_message(channel_id:, message_id:)
      translate_errors do
        Slack::Client.pin_message(
          workspace: @workspace,
          channel: channel_id,
          timestamp: message_id
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

    def update_message(channel_id:, message_id:, text:, blocks:)
      translate_errors do
        Slack::Client.update_message(
          workspace: @workspace,
          channel: channel_id,
          ts: message_id,
          text: text,
          blocks: blocks
        )

        { success: true }
      end
    end

    def delete_message(channel_id:, message_id:)
      translate_errors do
        Slack::Client.delete_message(
          workspace: @workspace,
          channel: channel_id,
          ts: message_id
        )

        { success: true }
      end
    end

    def get_message_permalink(channel_id:, message_id:)
      translate_errors do
        result = Slack::Client.get_permalink(
          workspace: @workspace,
          channel: channel_id,
          message_ts: message_id
        )

        { permalink: result[:permalink] }
      end
    end

    def fetch_message(channel_id:, message_id:)
      translate_errors do
        raw = Slack::Client.get_message(
          workspace: @workspace,
          channel: channel_id,
          ts: message_id
        )
        message = raw.is_a?(Hash) ? (raw[:message] || raw["message"] || raw) : {}

        {
          message_id: message[:ts] || message["ts"],
          channel_id: channel_id,
          user_id: message[:user] || message["user"],
          text: message[:text] || message["text"],
          posted_at: (message[:ts] || message["ts"])&.to_f&.then { |t| Time.at(t) },
          raw: message
        }
      end
    end

    def get_user_info(user_id:)
      translate_errors do
        raw = Slack::Client.get_user_info(workspace: @workspace, user_id: user_id)
        user = raw[:user] || raw["user"] || raw
        profile = user[:profile] || user["profile"] || {}

        {
          user_id: user[:id] || user["id"],
          display_name: profile[:display_name].presence || profile["display_name"].presence || user[:name] || user["name"],
          real_name: profile[:real_name] || profile["real_name"],
          avatar_url: profile[:image_192] || profile["image_192"] || profile[:image_48] || profile["image_48"],
          email: profile[:email] || profile["email"],
          timezone: user[:tz] || user["tz"],
          raw: user
        }
      end
    end

    def post_threaded_message(channel_id:, parent_message_id:, text:, blocks: nil)
      translate_errors do
        result = Slack::Client.post_message(
          workspace: @workspace,
          channel: channel_id,
          text: text,
          blocks: blocks,
          thread_ts: parent_message_id
        )

        { message_id: result[:ts] }
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

    def list_members
      translate_errors do
        raw_users = Slack::Client.list_users(workspace: @workspace)

        raw_users
          .reject { |u| u[:is_bot] || u[:deleted] || u[:id] == "USLACKBOT" }
          .map do |u|
            profile = u[:profile] || {}
            {
              id: u[:id],
              name: profile[:real_name].presence || profile[:display_name].presence || u[:name],
              avatarUrl: profile[:image_48]
            }
          end
      end
    end

    # Cached briefly: this backs pickers and display-name lookups that can be
    # hit several times per settings interaction, and conversations.list is
    # Tier 2 rate limited.
    def list_channels
      Rails.cache.fetch("slack:channels:#{@workspace.id}", expires_in: 1.minute) do
        translate_errors do
          raw_channels = Slack::Client.list_conversations(workspace: @workspace)

          raw_channels.map do |c|
            { id: c[:id], name: c[:name] }
          end
        end
      end
    end

    private

    def translate_errors
      yield
    rescue Slack::Client::AuthRevokedError => e
      Slack::AuthRevokedNotifier.notify(@workspace, error_code: e.error_code)
      raise AdapterError::AuthRevoked.new(e.error_code)
    rescue Slack::Client::RateLimitedError => e
      raise AdapterError::RateLimited.new(e.retry_after)
    rescue Slack::Client::TriggerExpiredError
      raise AdapterError::TriggerExpired, "Modal trigger expired"
    rescue Slack::Client::ChannelExistsError
      raise AdapterError::ChannelExists, "Channel name already taken"
    rescue Slack::Client::AlreadyArchivedError
      raise AdapterError::AlreadyArchived, "Channel is already archived"
    rescue Slack::Client::IsArchivedError
      raise AdapterError::IsArchived, "Channel is archived"
    rescue Slack::Client::NotInChannelError
      raise AdapterError::NotInChannel, "Bot not in channel"
    rescue Slack::Client::ChannelNotFoundError
      raise AdapterError::NotFound, "Channel not found"
    rescue Slack::Client::AlreadyInChannelError
      raise AdapterError::AlreadyInChannel, "User already in channel"
    rescue Slack::Client::RestrictedActionError
      raise AdapterError::RestrictedAction, "Action restricted by workspace policy"
    rescue Slack::Client::UnsafeDownloadHost => e
      raise AdapterError::UnsafeDownloadHost, e.message
    rescue Slack::Client::ApiError => e
      raise AdapterError, e.message
    end
  end
end
