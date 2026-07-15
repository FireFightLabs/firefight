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
    class NotArchivedError < ApiError; end
    class IsArchivedError < ApiError; end
    class NotInChannelError < ApiError; end
    class AlreadyInChannelError < ApiError; end
    class RestrictedActionError < ApiError; end
    class ServerError < ApiError; end
    class UnsafeDownloadHost < ApiError; end

    class AuthRevokedError < ApiError
      attr_reader :error_code

      def initialize(error_code)
        @error_code = error_code
        super("Slack auth revoked: #{error_code}")
      end
    end

    class RateLimitedError < ApiError
      attr_reader :retry_after

      def initialize(retry_after)
        @retry_after = retry_after
        super("Slack rate-limited; retry_after=#{retry_after}s")
      end
    end

    SLACK_ERROR_CODES = {
      "expired_trigger_id" => TriggerExpiredError,
      "name_taken"         => ChannelExistsError,
      "channel_not_found"  => ChannelNotFoundError,
      "already_archived"   => AlreadyArchivedError,
      "not_archived"       => NotArchivedError,
      "is_archived"        => IsArchivedError,
      "not_in_channel"     => NotInChannelError,
      "already_in_channel" => AlreadyInChannelError,
      "cant_invite_self"   => AlreadyInChannelError,
      "restricted_action"  => RestrictedActionError,
      "token_revoked"      => AuthRevokedError,
      "account_inactive"   => AuthRevokedError,
      "invalid_auth"       => AuthRevokedError,
      "not_authed"         => AuthRevokedError
    }.freeze

    # Open a modal in Slack
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param trigger_id [String] Slack trigger_id from slash command (expires in 3s)
    # @param view [Hash] Block Kit modal view JSON
    # @return [Hash] Slack API response with indifferent access
    # @raise [TriggerExpiredError] if trigger_id has expired
    # @raise [ApiError] if Slack API returns an error
    def self.open_modal(workspace:, trigger_id:, view:)
      api_post(
        workspace: workspace,
        endpoint: "views.open",
        payload: {
          trigger_id: trigger_id,
          view: view
        }
      )
    end

    def self.push_modal(workspace:, trigger_id:, view:)
      api_post(
        workspace: workspace,
        endpoint: "views.push",
        payload: {
          trigger_id: trigger_id,
          view: view
        }
      )
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
      api_post(
        workspace: workspace,
        endpoint: "conversations.create",
        payload: {
          name: name,
          is_private: is_private
        }
      )
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
    end

    def self.unarchive_channel(workspace:, channel:)
      api_post(
        workspace: workspace,
        endpoint: "conversations.unarchive",
        payload: {
          channel: channel
        }
      )
    rescue NotArchivedError
      { ok: true }
    end

    # List all channels in the workspace
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param types [String] Comma-separated list of channel types (default: "public_channel")
    # @return [Array<Hash>] Array of channel objects
    # @raise [ApiError] if Slack API returns an error
    def self.list_conversations(workspace:, types: "public_channel")
      channels = []
      cursor = nil

      # Paginate with a hard cap; conversations.list is Tier 2 rate limited.
      10.times do
        payload = { types: types, exclude_archived: true, limit: 200 }
        payload[:cursor] = cursor if cursor.present?

        body = api_post(workspace: workspace, endpoint: "conversations.list", payload: payload)
        channels.concat(body[:channels] || [])

        cursor = body.dig(:response_metadata, :next_cursor)
        break if cursor.blank?
      end

      channels
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
      api_get(workspace: workspace, endpoint: "users.info", params: { user: user_id })
    end

    # Allowlist so the workspace's Bearer token can't leak to a hostile host
    # via a forged `permalink_public` or misrouted URL.
    ALLOWED_DOWNLOAD_HOST_SUFFIX = ".slack.com"

    def self.download_file(workspace:, url:)
      uri = URI(url)
      host = uri.host.to_s.downcase
      unless host == "slack.com" || host.end_with?(ALLOWED_DOWNLOAD_HOST_SUFFIX)
        raise UnsafeDownloadHost, "refusing to send Slack token to host=#{host}"
      end

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{workspace.access_token}"

      response = pool_request(uri, request, endpoint: "files.download")

      # Slack private file URLs redirect to a presigned CDN URL. Follow the
      # redirect without the Bearer token — the presigned URL carries its own auth.
      # Auth failures redirect back to the Slack login page (same host, ?redir= param).
      if response.code.to_i.between?(301, 302) && response["location"].present?
        redirect_location = response["location"]
        redirect_uri = URI(redirect_location)

        if redirect_uri.query.to_s.include?("redir=")
          raise ApiError, "Slack file download redirected to auth page — bot may be missing files:read scope"
        end

        redirect_request = Net::HTTP::Get.new(redirect_uri)
        response = pool_request(redirect_uri, redirect_request, endpoint: "files.download.redirect")
      end

      unless response.code.to_i.between?(200, 299)
        raise ApiError, "Slack file download failed with status #{response.code}"
      end

      content_type = response["content-type"].to_s.split(";").first.strip
      raise ApiError, "Slack file download returned HTML — bot may be missing files:read scope" if content_type == "text/html"

      {
        body: response.body,
        content_type: content_type
      }
    end

    # Persistent HTTP connection pool for Slack API. Per-thread socket caches
    # are managed inside Net::HTTP::Persistent; the pool object is shared
    # across Puma threads.
    #
    # idle_timeout (30s): safely under typical AWS ALB / Slack edge idle
    # window (~60s); pool_request retries once if we ever reuse a half-closed
    # socket. open/read timeout: a wedged Slack endpoint can't pin a Puma
    # thread forever.
    OPEN_TIMEOUT_SECONDS    = 5
    READ_TIMEOUT_SECONDS    = 10
    IDLE_TIMEOUT_SECONDS    = 30
    MAX_RETRY_ATTEMPTS      = 3
    MAX_RATE_LIMIT_WAIT     = 5
    STALE_SOCKET_ERRORS     = [ EOFError, Errno::ECONNRESET, Errno::EPIPE, Net::HTTP::Persistent::Error ].freeze
    TRANSIENT_NETWORK_ERRORS = [ Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH ].freeze
    HTTP_POOL_MUTEX = Mutex.new

    def self.http_pool
      @http_pool ||= HTTP_POOL_MUTEX.synchronize do
        @http_pool ||= Net::HTTP::Persistent.new(name: "slack_api").tap do |pool|
          pool.idle_timeout = IDLE_TIMEOUT_SECONDS
          pool.open_timeout = OPEN_TIMEOUT_SECONDS
          pool.read_timeout = READ_TIMEOUT_SECONDS
        end
      end
    end

    def self.pool_request(uri, request, endpoint: nil)
      started_at  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      attempts    = 0
      retried_429 = false

      begin
        attempts += 1
        response = http_pool.request(uri, request)
        status   = response.code.to_i

        if status == 429
          retry_after = parse_retry_after(response["retry-after"])
          raise RateLimitedError.new(retry_after)
        elsif status.between?(500, 599)
          raise ServerError, "Slack API returned #{status}"
        end

        log_call(endpoint: endpoint, status: status, started_at: started_at, attempts: attempts)
        response
      rescue *STALE_SOCKET_ERRORS => e
        if attempts < 2
          Rails.logger.info({ event: "slack.client.stale_socket_retry", endpoint: endpoint, error_class: e.class.name })
          retry
        end
        log_error(endpoint: endpoint, error: e, started_at: started_at, attempts: attempts)
        raise
      rescue *TRANSIENT_NETWORK_ERRORS, ServerError => e
        if attempts < MAX_RETRY_ATTEMPTS
          sleep(backoff_seconds(attempts))
          Rails.logger.info({ event: "slack.client.retry", endpoint: endpoint, error_class: e.class.name, attempt: attempts })
          retry
        end
        log_error(endpoint: endpoint, error: e, started_at: started_at, attempts: attempts)
        raise
      rescue RateLimitedError => e
        unless retried_429
          retried_429 = true
          wait = [ e.retry_after, MAX_RATE_LIMIT_WAIT ].min
          Rails.logger.info({ event: "slack.client.rate_limit_retry", endpoint: endpoint, retry_after: e.retry_after, wait: wait })
          sleep(wait)
          retry
        end
        log_error(endpoint: endpoint, error: e, started_at: started_at, attempts: attempts)
        raise
      end
    end

    def self.parse_retry_after(header)
      Integer(header.to_s.strip)
    rescue ArgumentError, TypeError
      1
    end

    # ±50% jitter so concurrent callers don't synchronize on retry.
    def self.backoff_seconds(attempts)
      base = 0.25 * (2**(attempts - 1))
      base + (rand * base) - (base / 2.0)
    end

    def self.log_call(endpoint:, status:, started_at:, attempts:)
      Rails.logger.info({
        event:       "slack.client.call",
        endpoint:    endpoint,
        status:      status,
        attempts:    attempts,
        duration_ms: duration_ms_since(started_at)
      })
    end

    def self.log_error(endpoint:, error:, started_at:, attempts:)
      Rails.logger.warn({
        event:       "slack.client.error",
        endpoint:    endpoint,
        error_class: error.class.name,
        error:       error.message,
        attempts:    attempts,
        duration_ms: duration_ms_since(started_at)
      })
    end

    def self.duration_ms_since(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    private

    # Make a POST request to Slack API
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param endpoint [String] Slack API endpoint (e.g., "chat.postMessage")
    # @param payload [Hash] Request payload
    # @return [Hash] Parsed JSON response with indifferent access
    # @raise [ApiError] if request fails or Slack returns an error
    def self.api_get(workspace:, endpoint:, params: {})
      uri = URI("#{SLACK_API_BASE}/#{endpoint}")
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{workspace.access_token}"

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

    def self.api_post(workspace:, endpoint:, payload:)
      uri = URI("#{SLACK_API_BASE}/#{endpoint}")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{workspace.access_token}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = pool_request(uri, request, endpoint: endpoint)

      body = parse_json_body(response.body)
      return body if body[:ok]

      raise typed_error_for(body[:error], body)
    end

    def self.parse_json_body(raw)
      JSON.parse(raw).with_indifferent_access
    rescue JSON::ParserError => e
      raise ApiError, "Failed to parse Slack API response: #{e.message}"
    end

    def self.typed_error_for(error_code, body)
      klass = SLACK_ERROR_CODES[error_code]
      return AuthRevokedError.new(error_code) if klass == AuthRevokedError

      details = body.slice(:error, :response_metadata, :needed, :provided)
      message = "Slack API error: #{error_code} (details: #{details.to_json})"
      (klass || ApiError).new(message)
    end
  end
end
