# Test helper for creating OmniAuth mock data
module OmniauthTestHelper
  # Create a mock Slack OAuth response hash
  #
  # @param overrides [Hash] Custom values to override defaults
  # @return [OmniAuth::AuthHash] Mock OAuth hash
  def mock_slack_auth_hash(overrides = {})
    defaults = {
      provider: "slack",
      uid: "U12345678",
      info: {
        name: "Test User",
        email: "test@example.com",
        image: "https://example.com/avatar.jpg"
      },
      credentials: {
        token: "xoxb-test-token-12345",
        refresh_token: nil,
        expires_at: nil,
        expires: false
      },
      extra: {
        team_info: {
          "id" => "T12345678",
          "name" => "Test Workspace"
        },
        user_info: {
          "id" => "U12345678",
          "name" => "Test User",
          "email" => "test@example.com"
        },
        raw_info: {
          ok: true,
          app_id: "A12345678",
          authed_user: {
            id: "U12345678"
          },
          team: {
            id: "T12345678",
            name: "Test Workspace"
          },
          enterprise: nil,
          is_enterprise_install: false,
          token_type: "bot",
          access_token: "xoxb-test-token-12345",
          bot_user_id: "U12345678",
          scope: "team:read,commands,chat:write"
        }
      }
    }

    merged = deep_merge_hashes(defaults, overrides)

    # Convert to OmniAuth::AuthHash-like structure with dot notation access
    OmniAuth::AuthHash.new(merged)
  end

  # Create a mock Slack interaction payload
  #
  # @param type [String] Interaction type (block_actions, view_submission, etc.)
  # @param overrides [Hash] Custom values to override defaults
  # @return [Hash] Mock interaction payload
  def mock_slack_interaction_payload(type:, overrides: {})
    base = {
      "type" => type,
      "user" => {
        "id" => "U12345678",
        "username" => "testuser",
        "team_id" => "T12345678"
      },
      "team" => {
        "id" => "T12345678",
        "domain" => "test-workspace"
      },
      "api_app_id" => "A12345678",
      "token" => "verification_token"
    }

    case type
    when "block_actions"
      base.merge!({
        "trigger_id" => "12345.67890.trigger",
        "channel" => {
          "id" => "C12345678",
          "name" => "incidents"
        },
        "actions" => [
          {
            "action_id" => "preview_announcement",
            "block_id" => "block_id",
            "type" => "button"
          }
        ]
      })
    when "view_submission"
      base.merge!({
        "view" => {
          "id" => "V12345678",
          "type" => "modal",
          "callback_id" => "share_incidents_channel_modal",
          "state" => {
            "values" => {
              "share_target_block" => {
                "share_target_select" => {
                  "type" => "multi_conversations_select",
                  "selected_conversations" => ["C87654321"]
                }
              }
            }
          }
        }
      })
    end

    deep_merge_hashes(base, overrides)
  end

  private

  def deep_merge_hashes(hash1, hash2)
    hash1.merge(hash2) do |_key, v1, v2|
      if v1.is_a?(Hash) && v2.is_a?(Hash)
        deep_merge_hashes(v1, v2)
      else
        v2
      end
    end
  end
end
