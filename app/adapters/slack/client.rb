module Slack
  # Wrapper for Slack Web API calls
  class Client
    SLACK_API_BASE = "https://slack.com/api"

    class ApiError < StandardError; end
    class TriggerExpiredError < ApiError; end

    # Open a modal in Slack
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param trigger_id [String] Slack trigger_id from slash command (expires in 3s)
    # @param view [Hash] Block Kit modal view JSON
    # @return [Hash] Slack API response
    # @raise [TriggerExpiredError] if trigger_id has expired
    # @raise [ApiError] if Slack API returns an error
    def self.open_modal(workspace:, trigger_id:, view:)
      response = HTTParty.post(
        "#{SLACK_API_BASE}/views.open",
        headers: {
          "Authorization" => "Bearer #{workspace.access_token}",
          "Content-Type" => "application/json"
        },
        body: {
          trigger_id: trigger_id,
          view: view
        }.to_json
      )

      body = JSON.parse(response.body)

      unless body["ok"]
        error = body["error"]
        raise TriggerExpiredError, "Trigger ID expired" if error == "expired_trigger_id"
        raise ApiError, "Slack API error: #{error}"
      end

      body
    rescue JSON::ParserError => e
      raise ApiError, "Failed to parse Slack API response: #{e.message}"
    end

    # Post a message to a Slack channel
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param text [String] Message text
    # @param blocks [Array<Hash>] Optional Block Kit blocks
    # @return [Hash] Slack API response
    # @raise [ApiError] if Slack API returns an error
    def self.post_message(workspace:, channel:, text:, blocks: nil)
      response = HTTParty.post(
        "#{SLACK_API_BASE}/chat.postMessage",
        headers: {
          "Authorization" => "Bearer #{workspace.access_token}",
          "Content-Type" => "application/json"
        },
        body: {
          channel: channel,
          text: text,
          blocks: blocks
        }.compact.to_json
      )

      body = JSON.parse(response.body)

      unless body["ok"]
        raise ApiError, "Slack API error: #{body["error"]}"
      end

      body
    rescue JSON::ParserError => e
      raise ApiError, "Failed to parse Slack API response: #{e.message}"
    end

    # Post an ephemeral message (only visible to specific user)
    #
    # @param workspace [Workspace] The workspace to use for authentication
    # @param channel [String] Channel ID
    # @param user [String] User ID who will see the message
    # @param text [String] Message text
    # @return [Hash] Slack API response
    # @raise [ApiError] if Slack API returns an error
    def self.post_ephemeral(workspace:, channel:, user:, text:)
      response = HTTParty.post(
        "#{SLACK_API_BASE}/chat.postEphemeral",
        headers: {
          "Authorization" => "Bearer #{workspace.access_token}",
          "Content-Type" => "application/json"
        },
        body: {
          channel: channel,
          user: user,
          text: text
        }.to_json
      )

      body = JSON.parse(response.body)

      unless body["ok"]
        raise ApiError, "Slack API error: #{body["error"]}"
      end

      body
    rescue JSON::ParserError => e
      raise ApiError, "Failed to parse Slack API response: #{e.message}"
    end
  end
end
