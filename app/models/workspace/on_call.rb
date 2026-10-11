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
    live = self.class.with_connection { |connection| Investigation::LIVE_STATUSES.map { |status| connection.quote(status) }.join(", ") }
    micros = FirefightAi::AgentLoop::MICROS_PER_CENT
    investigations.seen.where(trigger_source: Investigation::TRIGGER_ALERT, created_at: STORM_WINDOW.ago..)
                  .sum(Arel.sql("CASE WHEN status IN (#{live}) THEN max_spend_cents * #{micros} ELSE spent_micros END")).fdiv(micros).ceil
  end

  def storm_budget_left_cents = [ alert_storm_ceiling_cents - storm_committed_cents, 0 ].max

  # Holds the workspace's storm budget for the length of a transaction, so alerts starting runs at the same moment
  # count on it one at a time.
  def lock_storm_budget!
    key = Zlib.crc32("alert_storm:#{id}")
    sql = self.class.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)::text", key ])
    self.class.with_connection { |connection| connection.select_value(sql) }
  end

  def shown_storm_ceiling = "$#{format('%.2f', alert_storm_ceiling_cents / 100.0).delete_suffix('.00')}"

  # The paging connection a page goes through: the one named, by its slug or its name, or the only one there is when
  # none is named. nil when that does not tell one.
  def paging_connection(named, among: Integrations::Paging.connections(self))
    return among.first if named.blank? && among.one?

    wanted = named.to_s.strip
    among.find { |integration| [ integration.slug, integration.name, integration.display_name ].any? { |name| name.casecmp?(wanted) } }
  end

  # Grants Firefight paging the tools a paging connection is raised and kept in step through, and nothing more, through
  # the same grants the Permissions screen writes. A connection's tools arrive switched on, so connecting is the
  # decision, the same as the investigator's read pack.
  def grant_paging!(integration)
    integration.tools.available.enabled.where(name: Integrations::Paging.sync_tools(integration.provider)).find_each do |tool|
      Ability::Grant.grant!(workspace: self, principal: SystemAgent.paging, target: { action: tool.ability_action || tool.sync_ability_action! })
    end
  end

  # Why Firefight cannot raise a page through the connection or keep its pages in step, or nil when it can.
  def paging_blocked_reason(integration)
    paging_tools_blocked_reason(integration) || paging_grants_blocked_reason(integration)
  end

  # Why granting again would not let Firefight page through the connection, or nil when it would.
  def paging_grant_blocked_reason(integration)
    return paging_tools_blocked_reason(integration) if paging_tools_blocked_reason(integration)

    "Firefight paging already holds every tool it needs on #{integration.display_name}." if paging_grants_lost(integration).empty?
  end

  # A tool paging needs that the connection does not offer or has switched off, which only Integrations puts right.
  def paging_tools_blocked_reason(integration)
    names = Integrations::Paging.sync_tools(integration.provider)
    tools = integration.tools.available.where(name: names).index_by(&:name)
    missing = names - tools.keys
    return "#{integration.display_name} offers no #{missing.to_sentence}. Refresh its tools under Integrations." if missing.any?

    off = tools.values.reject(&:enabled?).map(&:name)
    "#{integration.display_name}'s #{off.to_sentence} #{off.one? ? 'is' : 'are'} switched off under Integrations." if off.any?
  end

  def paging_grants_blocked_reason(integration)
    lost = paging_grants_lost(integration)
    "Firefight paging no longer holds #{lost.to_sentence}, so it cannot page through #{integration.display_name} or keep its pages in step." if lost.any?
  end

  # The connection's paging tools Firefight paging no longer holds, which granting again gives back.
  def paging_grants_lost(integration)
    held = Ability::Resolver.resolve(SystemAgent.paging, self)
    integration.tools.available.where(name: Integrations::Paging.sync_tools(integration.provider)).map(&:action_key).reject { |key| held.covers?(key) }
  end

  # The alert source whose webhook brings back what people do to the connection's pages in the tool, or nil.
  def paging_return_source(integration)
    alert_sources.enabled.order(:created_at).find_by(provider: Integrations::Paging.alert_source_of(integration.provider))
  end
end
