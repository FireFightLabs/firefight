# What Settings, Workspace lets an admin change, from the dashboard and over MCP alike, so the list lives once.
module Workspace::Settings
  extend ActiveSupport::Concern

  KEYS = %i[transcript_access_enabled transcript_retention_days archive_channel_delay].freeze

  def settings
    KEYS.index_with { |key| public_send(key) }
  end

  def update_settings!(changes)
    update!(changes.to_h.symbolize_keys.slice(*KEYS))
  end
end
