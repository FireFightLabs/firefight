# A problem Halon raised on its own, from a scheduled check or a security event, and what it last said about it. It is
# the memory that keeps Halon quiet: one row per problem (key), said once, then said again only when it got worse
# (Investigation::Notice::NEWS), or when it comes back after a long time unseen. It is said in the channel of the
# team that owns what it is about, else the workspace's monitoring channel.
class Investigation::Notice < ApplicationRecord
  SIGNAL_DISK = "disk".freeze
  SIGNAL_CERTIFICATE = "certificate".freeze
  SIGNAL_ERROR_BUDGET = "error_budget".freeze
  SIGNAL_COST = "cost".freeze
  SIGNAL_LEAKED_SECRET = "leaked_secret".freeze
  SIGNAL_OTHER = "other".freeze
  SIGNALS = [ SIGNAL_DISK, SIGNAL_CERTIFICATE, SIGNAL_ERROR_BUDGET, SIGNAL_COST, SIGNAL_LEAKED_SECRET, SIGNAL_OTHER ].freeze
  SIGNAL_LABELS = {
    SIGNAL_DISK => "Disk space", SIGNAL_CERTIFICATE => "Certificate", SIGNAL_ERROR_BUDGET => "Error budget",
    SIGNAL_COST => "Cost", SIGNAL_LEAKED_SECRET => "Leaked secret", SIGNAL_OTHER => "Other"
  }.freeze

  # How soon a person needs to act. low is worth knowing, medium needs doing within weeks, high needs doing now.
  SEVERITY_LOW = "low".freeze
  SEVERITY_MEDIUM = "medium".freeze
  SEVERITY_HIGH = "high".freeze
  SEVERITIES = [ SEVERITY_LOW, SEVERITY_MEDIUM, SEVERITY_HIGH ].freeze
  SEVERITY_LABELS = { SEVERITY_LOW => "Worth knowing", SEVERITY_MEDIUM => "Needs doing within weeks", SEVERITY_HIGH => "Needs doing now" }.freeze

  # A problem not seen for this long that shows up again is news again.
  RESURFACE_AFTER = 14.days
  # A date has to move this share of the time that was left, and at least a day, to count as worse, so a disk whose
  # forecast wobbles by a day each run is not said again every day.
  EARLIER_SHARE = 0.25
  TOPIC_LIMIT = 120
  SUMMARY_LIMIT = 1000

  belongs_to :workspace
  belongs_to :check, class_name: "Investigation::Check", optional: true, inverse_of: :notices
  belongs_to :investigation, optional: true
  belongs_to :resource, class_name: "ResourceMap::Resource", optional: true

  validates :key, :topic, :summary, presence: true
  validates :signal, inclusion: { in: SIGNALS }
  validates :severity, inclusion: { in: SEVERITIES }

  scope :recent, -> { order(last_seen_at: :desc) }
  scope :unsaid, -> { where(unsaid: true) }

  # What one reading says about a problem, before it is compared with what was said.
  # reference is the provider's own name for one report, such as an alert, when one resource can hold several.
  Reading = Data.define(:signal, :topic, :summary, :severity, :due_on, :resource, :reference) do
    def initialize(due_on: nil, resource: nil, reference: nil, **) = super

    def key = Investigation::Notice.key_for(signal, resource: resource, topic: topic, reference: reference)
  end

  # The same problem gets the same key every time: the provider's reference when it has one, its resource on the map
  # when it is about one, else its topic in words.
  def self.key_for(signal, resource: nil, topic: nil, reference: nil)
    "#{signal}:#{reference.presence || resource&.id || topic.to_s.parameterize.presence || 'general'}"
  end

  def self.severity_rank(severity) = SEVERITIES.index(severity.to_s) || 0

  # Records what a run read, and answers the notice when it has to be said, nil when saying it again would be noise.
  # Whether it is news is decided in the statement that writes it (NEWS), never read first, so two runs reading the same
  # problem at once agree. Saying it is claimed with claim! the same way, so only one of them posts it.
  def self.observe!(workspace, reading, check: nil, investigation: nil, now: Time.current)
    seen = seen_values(reading, now).merge(check_id: check&.id, investigation_id: investigation&.id).compact
    inserted = insert_all([ seen.merge(workspace_id: workspace.id, key: reading.key, unsaid: true, created_at: now, updated_at: now) ],
                          unique_by: %i[workspace_id key], returning: %w[id])
    return find(inserted.rows.first.first) if inserted.rows.any?

    row = where(workspace_id: workspace.id, key: reading.key)
    binds = { resurface: now - RESURFACE_AFTER, rank: severity_rank(reading.severity), due: reading.due_on, today: now.to_date }
    news = row.where(sanitize_sql([ NEWS, binds ])).update_all(seen.merge(unsaid: true, updated_at: now)) > 0
    row.update_all(seen.merge(updated_at: now)) unless news
    news ? row.first : nil
  end

  # What a reading changes on its row, whatever it decides.
  def self.seen_values(reading, now)
    {
      signal: reading.signal, topic: reading.topic.to_s.squish.truncate(TOPIC_LIMIT), summary: reading.summary.to_s.strip.truncate(SUMMARY_LIMIT),
      severity: reading.severity, due_on: reading.due_on, resource_id: reading.resource&.id, last_seen_at: now
    }
  end
  private_class_method :seen_values

  RANK_SQL = "(CASE investigation_notices.severity #{SEVERITIES.each_with_index.map { |severity, index| "WHEN '#{severity}' THEN #{index}" }.join(' ')} ELSE 0 END)".freeze
  # A reading is news when the problem was never said, was unseen for long, is more urgent, or is due sooner by at least
  # EARLIER_SHARE of the time that was left and at least a day, so a forecast that wobbles by a day is not said again.
  NEWS = <<~SQL.squish.freeze
    (investigation_notices.last_said_at IS NULL
      OR investigation_notices.last_seen_at < :resurface
      OR #{RANK_SQL} < :rank
      OR (CAST(:due AS date) IS NOT NULL AND (investigation_notices.due_on IS NULL
        OR investigation_notices.due_on - CAST(:due AS date) >= GREATEST(CEIL((investigation_notices.due_on - CAST(:today AS date)) * #{EARLIER_SHARE}), 1))))
  SQL

  # Takes a notice to say it, in one statement, so two deliveries never both post it. false when another took it.
  def claim!
    taken = self.class.where(id: id, unsaid: true).update_all(unsaid: false, updated_at: Time.current) > 0
    reload if taken
    taken
  end

  # Once the platform took it, so a notice whose post failed is said again at the next run.
  def said!(channel_id:, message_id:, at: Time.current)
    update!(channel_id: channel_id, message_id: message_id, last_said_at: at, first_said_at: first_said_at || at, times_said: times_said + 1,
            unsaid: false, unsaid_reason: nil)
  end

  # The channel of the team that owns the resource, from the catalog: a service's own channel first, then its owning
  # team's. Without one, the workspace's monitoring channel, and nil when that is not set either.
  def self.channel_for(workspace, resource)
    owned = resource && owning_channel(resource)
    owned || workspace.halon_monitoring_channel.presence
  end

  def self.owning_channel(resource)
    entries = resource.catalog_entries.active.includes(:catalog_type).to_a
    teams, services = entries.partition { |entry| entry.catalog_type.system_key == CatalogType::SYSTEM_KEY_TEAM }
    own = services.filter_map { |entry| channel_of(entry) }.first
    own || (teams + services.flat_map(&:owning_teams)).uniq.filter_map { |team| channel_of(team) }.first
  end

  def self.channel_of(entry) = entry.role_value(CatalogAttributeDefinition::ROLE_NOTIFICATION_CHANNEL).presence
  private_class_method :owning_channel, :channel_of

  def channel = self.class.channel_for(workspace, resource)

  NO_CHANNEL = "No team channel or monitoring channel to say it in. Set a monitoring channel and Halon says it at the next run.".freeze
  NOT_STARTED = "Halon could not start on it. It tries again when the alert is reported again.".freeze
  RUN_PAGE_ONLY = "No team channel or monitoring channel to say it in, so Halon looked into it on the run's page only.".freeze
  NOT_DELIVERED = "Firefight could not post in that channel. Add the Firefight app to it, and Halon says this at the next run.".freeze

  # Kept unsaid with why, so the next run says it once there is somewhere to.
  def unsaid_because!(reason) = update_columns(unsaid: true, unsaid_reason: reason, updated_at: Time.current)

  def due_words
    return nil unless due_on

    "around #{due_on.strftime('%b %-d')}"
  end
end
