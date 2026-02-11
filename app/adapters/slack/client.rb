module Slack
  # Wrapper for Slack Web API calls
  class Client
    SLACK_API_BASE = "https://slack.com/api"

    class ApiError < StandardError; end
    class TriggerExpiredError < ApiError; end
    class ChannelExistsError < ApiError; end
    class ChannelNotFoundError < ApiError; end

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

    # Post a message to a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param text [String] Message text
    # @param blocks [Array<Hash>] Optional Block Kit blocks
    # @return [Hash] Slack API response with indifferent access
    # @raise [ApiError] if Slack API returns an error
    def self.post_message(workspace:, channel:, text:, blocks: nil)
      api_post(
        workspace: workspace,
        endpoint: "chat.postMessage",
        payload: {
          channel: channel,
          text: text,
          blocks: blocks
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
    end

    # Pin a message in a channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param timestamp [String] Message timestamp to pin
    # @return [Hash] Slack API response
    # @raise [ApiError] if Slack API returns an error
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

    private

    # Make a POST request to Slack API
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param endpoint [String] Slack API endpoint (e.g., "chat.postMessage")
    # @param payload [Hash] Request payload
    # @return [Hash] Parsed JSON response with indifferent access
    # @raise [ApiError] if request fails or Slack returns an error
    def self.api_post(workspace:, endpoint:, payload:)
      response = HTTParty.post(
        "#{SLACK_API_BASE}/#{endpoint}",
        headers: {
          "Authorization" => "Bearer #{workspace.access_token}",
          "Content-Type" => "application/json"
        },
        body: payload.to_json
      )

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
