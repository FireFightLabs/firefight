# A workspace can start before its team connects a chat platform. Until it does, nothing can reach the team, so
# incidents, which run in channels, wait for it. Disconnection is Workspace::Connection, an install that went away.
module Workspace::ChatConnection
  extend ActiveSupport::Concern

  INCIDENTS_BLOCKED_MESSAGE = "Connect Slack first to run incidents.".freeze

  class AlreadyConnected < StandardError; end

  included do
    validates :platform_id, :installed_at, presence: true, if: :platform?
    validates :platform, presence: true, if: :platform_id?
    validates :platform_id, uniqueness: { scope: :platform }, allow_nil: true

    scope :chat_connected, -> { where.not(platform: nil) }
  end

  def chat_connected?
    platform.present?
  end

  def incidents_blocked_reason
    INCIDENTS_BLOCKED_MESSAGE unless chat_connected?
  end

  # The name stays the one the team chose when it signed up. The row is locked so two installs finishing at once
  # cannot both connect it.
  def connect_slack!(auth_hash)
    lock!
    raise AlreadyConnected, "Workspace #{id} is already connected" if chat_connected?

    team_info = auth_hash.extra.team_info
    update!(
      platform: Platforms::SLACK,
      platform_id: team_info["id"],
      platform_data: team_info,
      access_token: auth_hash.credentials.token,
      refresh_token: auth_hash.credentials.refresh_token,
      token_expires_at: auth_hash.credentials.expires_at ? Time.at(auth_hash.credentials.expires_at) : nil,
      installed_at: Time.current,
      disconnected_at: nil,
      disconnected_reason: nil
    )
  end
end
