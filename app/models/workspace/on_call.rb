# What a team sets for the hours nobody is watching: whether an alert that opens an incident starts Halon, how much those
# runs may spend together in an hour, and whether Halon pages whoever is on call with what it found.
module Workspace::OnCall
  extend ActiveSupport::Concern

  # A storm is judged over the last hour, so a burst of alerts shares one budget and the next hour starts fresh.
  STORM_WINDOW = 1.hour
  # Less than this left of the hour's ceiling buys a run too few turns to find anything, so none starts.
  MIN_ALERT_RUN_CENTS = 50
  MAX_STORM_CEILING_CENTS = 100_000

  included do
    validates :alert_storm_ceiling_cents, numericality: { only_integer: true, greater_than_or_equal_to: MIN_ALERT_RUN_CENTS,
                                                          less_than_or_equal_to: MAX_STORM_CEILING_CENTS }
  end

  # What runs started by alerts in the last hour hold of the ceiling: what a finished run spent, and all a live one may
  # still spend, so two alerts at once never both count on the same money.
  def storm_committed_cents
    live = Investigation::LIVE_STATUSES.map { |status| self.class.connection.quote(status) }.join(", ")
    micros = FirefightAi::AgentLoop::MICROS_PER_CENT
    investigations.seen.where(trigger_source: Investigation::TRIGGER_ALERT, created_at: STORM_WINDOW.ago..)
                  .sum(Arel.sql("CASE WHEN status IN (#{live}) THEN max_spend_cents * #{micros} ELSE spent_micros END")).fdiv(micros).ceil
  end

  def storm_budget_left_cents = [ alert_storm_ceiling_cents - storm_committed_cents, 0 ].max

  # Holds the workspace's storm budget for the length of a transaction, so alerts starting runs at the same moment
  # count on it one at a time.
  def lock_storm_budget!
    key = Zlib.crc32("alert_storm:#{id}")
    self.class.connection.select_value(self.class.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ]))
  end

  def shown_storm_ceiling = "$#{format('%.2f', alert_storm_ceiling_cents / 100.0).delete_suffix('.00')}"
end
