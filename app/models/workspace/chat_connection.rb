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
  def connect_chat!(install)
    lock!
    raise AlreadyConnected, "Workspace #{id} is already connected" if chat_connected?

    update!(platform: install.fetch(:platform), platform_id: install.fetch(:platform_id), installed_at: Time.current,
            **self.class.chat_install_attributes(install))
  end

  # Installing again grants what the app asks for now, such as a new scope, to the team already connected. The name and
  # everything set up in the team stay as they are.
  def reinstall_chat!(install)
    update!(**self.class.chat_install_attributes(install))
  end

  # The team's own name in the chat platform, which can differ from the workspace's.
  def chat_team_name
    platform_data&.dig("name").presence || name if chat_connected?
  end

  # Sets one key of what the platform keeps on the workspace, in one statement so a write beside it is never lost.
  def remember_platform_data!(key, value)
    self.class.where(id: id)
        .update_all([ "platform_data = COALESCE(platform_data, '{}'::jsonb) || jsonb_build_object(?::text, ?::text)", key, value ])
    self.platform_data = platform_data.to_h.merge(key => value)
  end
end
