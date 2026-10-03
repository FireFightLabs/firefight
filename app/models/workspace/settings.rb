# What Settings, Workspace lets an admin change, from the dashboard and over MCP alike, so the list lives once.
module Workspace::Settings
  extend ActiveSupport::Concern

  KEYS = %i[transcript_access_enabled transcript_retention_days archive_channel_delay web_search_enabled halon_regression_enabled].freeze

  def settings
    KEYS.index_with { |key| public_send(key) }
  end

  # Firefight pays for web lookups, so a workspace has a day's worth, counted from the ledger that holds every one.
  WEB_LOOKUPS_PER_DAY = 1_000

  def web_lookup_blocked_reason
    return "Web search is switched off for this workspace." unless web_search_enabled?

    used = Ability::Invocation.where(workspace: self, action_key: Ability::Action::WEB_READ).where(created_at: 1.day.ago..).count
    "This workspace has used its #{WEB_LOOKUPS_PER_DAY} web lookups for the day." if used >= WEB_LOOKUPS_PER_DAY
  end

  def update_settings!(changes)
    update!(changes.to_h.symbolize_keys.slice(*KEYS))
  end
end
