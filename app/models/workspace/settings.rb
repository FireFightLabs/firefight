# What Settings, Workspace lets an admin change, from the dashboard and over MCP alike, so the list lives once.
module Workspace::Settings
  extend ActiveSupport::Concern

  KEYS = %i[transcript_access_enabled transcript_retention_days archive_channel_delay web_search_enabled halon_regression_enabled
            memory_expiry_days code_fix_agent issue_tracker issue_creation issue_tracker_target issue_webhook_secret
            alert_investigations_enabled alert_storm_ceiling_cents on_call_paging_enabled].freeze
  # Taken, never shown again, so what is read back says only whether one is saved.
  WRITE_ONLY = %i[issue_webhook_secret].freeze
  # What a form may send, a hash where the setting holds one.
  PERMITTED = [ *(KEYS - %i[issue_tracker_target]), { issue_tracker_target: {} } ].freeze

  def settings
    (KEYS - WRITE_ONLY).index_with { |key| public_send(key) }.merge(issue_webhook_secret_set: issue_webhook_secret_set?)
  end

  # Firefight pays for web lookups, so a workspace has a day's worth, counted from the ledger that holds every one.
  WEB_LOOKUPS_PER_DAY = 1_000

  def web_lookup_blocked_reason
    return "Web search is switched off for this workspace." unless web_search_enabled?

    used = Ability::Invocation.where(workspace: self, action_key: Ability::Action::WEB_READ).where(created_at: 1.day.ago..).count
    "This workspace has used its #{WEB_LOOKUPS_PER_DAY} web lookups for the day." if used >= WEB_LOOKUPS_PER_DAY
  end

  # A write-only setting left empty keeps what is saved, since the page never has it to send back.
  def update_settings!(changes)
    given = changes.to_h.symbolize_keys.slice(*KEYS).reject { |key, value| WRITE_ONLY.include?(key) && value.blank? }
    transaction do
      update!(given.except(*WRITE_ONLY))
      save_issue_webhook_secret!(given[:issue_webhook_secret]) if given.key?(:issue_webhook_secret)
    end
  end
end
