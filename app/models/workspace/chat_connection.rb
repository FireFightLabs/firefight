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
    scope :chat_unconnected, -> { where(platform: nil) }
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

    update!(platform: Platforms::SLACK, platform_id: auth_hash.extra.team_info["id"], installed_at: Time.current,
            **self.class.slack_install_attributes(auth_hash))
  end

  # Installing again grants what the app asks for now, such as a new scope, to the team already connected. The name and
  # everything set up in the team stay as they are.
  def reinstall_slack!(auth_hash)
    update!(**self.class.slack_install_attributes(auth_hash))
  end

  # The team's own name in the chat platform, which can differ from the workspace's.
  def chat_team_name
    platform_data&.dig("name").presence || name if chat_connected?
  end
end
