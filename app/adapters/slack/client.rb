require "net/http/persistent"

module Slack
  # Wrapper for Slack Web API calls
  class Client
    SLACK_API_BASE = "https://slack.com/api"

    class ApiError < StandardError; end
    class TriggerExpiredError < ApiError; end
    class ChannelExistsError < ApiError; end
    class ChannelNotFoundError < ApiError; end
    class AlreadyArchivedError < ApiError; end
    class AlreadyInChannelError < ApiError; end

    # Open a modal in Slack
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param trigger_id [String] Slack trigger_id from slash command (expires in 3s)
    # @param view [Hash] Block Kit modal view JSON
    # @return [Hash] Slack API response with indifferent access
    # @raise [TriggerExpiredError] if trigger_id has expired
    # @raise [ApiError] if Slack API returns an error
    def self.open_modal(workspace:, trigger_id:, view:)
      body = api_post(
        workspace: workspace,
        endpoint: "views.open",
        payload: {
          trigger_id: trigger_id,
          view: view
        }
      )

      if !body[:ok] && body[:error] == "expired_trigger_id"
        raise TriggerExpiredError, "Trigger ID expired"
      end

      body
    end

    def self.push_modal(workspace:, trigger_id:, view:)
      body = api_post(
        workspace: workspace,
        endpoint: "views.push",
        payload: {
          trigger_id: trigger_id,
          view: view
        }
      )

      if !body[:ok] && body[:error] == "expired_trigger_id"
        raise TriggerExpiredError, "Trigger ID expired"
      end

      body
    end

    # Post a message to a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param text [String] Message text
    # @param blocks [Array<Hash>] Optional Block Kit blocks
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.post_message(workspace:, channel:, text:, blocks: nil, thread_ts: nil)
      api_post(
        workspace: workspace,
        endpoint: "chat.postMessage",
        payload: {
          channel: channel,
          text: text,
          blocks: blocks,
          thread_ts: thread_ts
        }.compact
      )
    end

    # Post an ephemeral message (only visible to specific user)
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param user [String] User ID who will see the message
    # @param text [String] Message text
    # @param blocks [Array<Hash>] Optional Block Kit blocks
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.post_ephemeral(workspace:, channel:, user:, text:, blocks: nil)
      api_post(
        workspace: workspace,
        endpoint: "chat.postEphemeral",
        payload: {
          channel: channel,
          user: user,
          text: text,
          blocks: blocks
        }.compact
      )
    end

    # Create a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param name [String] Channel name
    # @param is_private [Boolean] Whether the channel should be private
    # @return [Hash] Slack API response with indifferent access
    # @raise [ChannelExistsError] if channel name already exists
    # @raise [ApiError] if Slack API returns an error
    # @see https://api.slack.com/methods/conversations.create
    def self.create_channel(workspace:, name:, is_private: false)
      body = api_post(
        workspace: workspace,
        endpoint: "conversations.create",
        payload: {
          name: name,
          is_private: is_private
        }
      )

      body
    rescue ApiError => e
      # Check if this is a "channel already exists" error
      if e.message.include?("name_taken")
        raise ChannelExistsError, "Channel '#{name}' already exists"
      else
        raise # Re-raise other ApiErrors
      end
    end

    # Set channel topic
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param topic [String] New topic text
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.set_channel_topic(workspace:, channel:, topic:)
      api_post(
        workspace: workspace,
        endpoint: "conversations.setTopic",
        payload: {
          channel: channel,
          topic: topic
        }
      )
    end

    # Set channel purpose (description)
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param purpose [String] New purpose text
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.set_channel_purpose(workspace:, channel:, purpose:)
      api_post(
        workspace: workspace,
        endpoint: "conversations.setPurpose",
        payload: {
          channel: channel,
          purpose: purpose
        }
      )
    end

    # Invite users to a channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param users [Array<String>, String] User IDs to invite (array or comma-separated string)
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.invite_to_channel(workspace:, channel:, users:)
      users_str = if users.is_a?(Array)
        users.join(",")
      else
        users.to_s
      end

      api_post(
        workspace: workspace,
        endpoint: "conversations.invite",
        payload: {
          channel: channel,
          users: users_str
        }
      )
    rescue ApiError => e
      if e.message.include?("already_in_channel") || e.message.include?("cant_invite_self")
        raise AlreadyInChannelError, "User(s) already in channel '#{channel}'"
      else
        raise
      end
    end

    # Pin a message in a channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param timestamp [String] Message timestamp to pin
    # @return [Hash] Slack API response
    # @raise [ApiError] if Slack API returns an error
    def self.add_reaction(workspace:, channel:, timestamp:, name:)
      api_post(
        workspace: workspace,
        endpoint: "reactions.add",
        payload: {
          channel: channel,
          timestamp: timestamp,
          name: name
        }
      )
    end

    def self.pin_message(workspace:, channel:, timestamp:)
      api_post(
        workspace: workspace,
        endpoint: "pins.add",
        payload: {
          channel: channel,
          timestamp: timestamp
        }
      )
    end

    # Update an existing message in a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param ts [String] Timestamp of the message to update
    # @param text [String] New message text
    # @param blocks [Array<Hash>] Optional Block Kit blocks
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.update_message(workspace:, channel:, ts:, text:, blocks: nil)
      api_post(
        workspace: workspace,
        endpoint: "chat.update",
        payload: {
          channel: channel,
          ts: ts,
          text: text,
          blocks: blocks
        }.compact
      )
    end

    # Delete a message from a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param ts [String] Timestamp of the message to delete
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.delete_message(workspace:, channel:, ts:)
      api_post(
        workspace: workspace,
        endpoint: "chat.delete",
        payload: {
          channel: channel,
          ts: ts
        }
      )
    end

    # Update an existing modal in Slack
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param view_id [String] The ID of the view to update
    # @param view [Hash] Updated Block Kit modal view JSON
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.update_modal(workspace:, view_id:, view:)
      api_post(
        workspace: workspace,
        endpoint: "views.update",
        payload: {
          view_id: view_id,
          view: view
        }
      )
    end

    # Archive a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @return [Hash] Slack API response with indifferent access
    # @raise [AlreadyArchivedError] if channel is already archived
    # @raise [ApiError] if Slack API returns an error
    def self.archive_channel(workspace:, channel:)
      api_post(
        workspace: workspace,
        endpoint: "conversations.archive",
        payload: {
          channel: channel
        }
      )
    rescue ApiError => e
      if e.message.include?("already_archived")
        raise AlreadyArchivedError, "Channel '#{channel}' is already archived"
      else
        raise
      end
    end

    def self.unarchive_channel(workspace:, channel:)
      api_post(
        workspace: workspace,
        endpoint: "conversations.unarchive",
        payload: {
          channel: channel
        }
      )
    rescue ApiError => e
      if e.message.include?("not_archived")
        { ok: true }
      else
        raise
      end
    end

    # List all channels in the workspace
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param types [String] Comma-separated list of channel types (default: "public_channel")
    # @return [Array<Hash>] Array of channel objects
    # @raise [ApiError] if Slack API returns an error
    def self.list_conversations(workspace:, types: "public_channel")
      body = api_post(
        workspace: workspace,
        endpoint: "conversations.list",
        payload: {
          types: types,
          exclude_archived: true
        }
      )

      body[:channels] || []
    end

    def self.list_users(workspace:)
      users = []
      cursor = nil

      loop do
        payload = { limit: 200 }
        payload[:cursor] = cursor if cursor.present?

        body = api_post(
          workspace: workspace,
          endpoint: "users.list",
          payload: payload
        )

        users.concat(body[:members] || [])
        cursor = body.dig(:response_metadata, :next_cursor)
        break if cursor.blank?
      end

      users
    end

    def self.get_permalink(workspace:, channel:, message_ts:)
      body = api_post(
        workspace: workspace,
        endpoint: "chat.getPermalink",
        payload: {
          channel: channel,
          message_ts: message_ts
        }
      )

      body
    end

    def self.get_message(workspace:, channel:, ts:)
      body = api_post(
        workspace: workspace,
        endpoint: "conversations.history",
        payload: {
          channel: channel,
          latest: ts,
          limit: 1,
          inclusive: true
        }
      )

      body[:messages]&.first
    end

    def self.get_user_info(workspace:, user_id:)
      api_post(
        workspace: workspace,
        endpoint: "users.info",
        payload: { user: user_id }
      )
    end

    def self.download_file(workspace:, url:)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{workspace.access_token}"

      response = pool_request(uri, request)

      unless response.code.to_i.between?(200, 299)
        raise ApiError, "Slack file download failed with status #{response.code}"
      end

      {
        body: response.body,
        content_type: response["content-type"]
      }
    end

    # Persistent HTTP connection pool for Slack API.
    # Reuses TCP+TLS sockets across calls, eliminating handshake overhead
    # (~15-20ms per call) on the warm path. Net::HTTP::Persistent maintains
    # per-thread connection caches internally, so the pool object is shared
    # across Puma threads but each thread has its own socket cache.
    #
    # idle_timeout: 30s — safely under the typical AWS ALB / Slack edge idle
    # window (~60s). Pairs with pool_request's stale-socket retry: if we ever
    # do reuse a half-closed socket, the second attempt opens a fresh one.
    STALE_SOCKET_ERRORS = [ EOFError, Errno::ECONNRESET, Errno::EPIPE, Net::HTTP::Persistent::Error ].freeze
    HTTP_POOL_MUTEX = Mutex.new

    def self.http_pool
      @http_pool || HTTP_POOL_MUTEX.synchronize do
        @http_pool ||= Net::HTTP::Persistent.new(name: "slack_api").tap do |pool|
          pool.idle_timeout = 30
        end
      end
    end

    # Wraps http_pool.request with a single retry on stale-socket errors.
    # Net::HTTP::Persistent.retry_change_requests defaults to false, so it
    # won't auto-retry POSTs — we do it here. One retry only: if both attempts
    # die at the connection level the underlying issue isn't a stale socket.
    def self.pool_request(uri, request)
      attempts = 0
      begin
        attempts += 1
        http_pool.request(uri, request)
      rescue *STALE_SOCKET_ERRORS => e
        raise if attempts >= 2

        Rails.logger.info({ event: "slack.client.stale_socket_retry", error_class: e.class.name, error: e.message })
        retry
      end
    end

    private

    # Make a POST request to Slack API
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param endpoint [String] Slack API endpoint (e.g., "chat.postMessage")
    # @param payload [Hash] Request payload
    # @return [Hash] Parsed JSON response with indifferent access
    # @raise [ApiError] if request fails or Slack returns an error
    def self.api_post(workspace:, endpoint:, payload:)
      uri = URI("#{SLACK_API_BASE}/#{endpoint}")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{workspace.access_token}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = pool_request(uri, request)
      body = JSON.parse(response.body).with_indifferent_access

      unless body[:ok]
        error_details = body.slice(:error, :response_metadata, :needed, :provided)
        raise ApiError, "Slack API error: #{body[:error]} (details: #{error_details.to_json})"
      end

      body
    rescue JSON::ParserError => e
      raise ApiError, "Failed to parse Slack API response: #{e.message}"
    end
  end
end
