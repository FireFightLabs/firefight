class Alert < ApplicationRecord
  STATUS_FIRING = "firing"
  STATUS_RESOLVED = "resolved"
  STATUSES = [ STATUS_FIRING, STATUS_RESOLVED ].freeze

  ROUTING_PENDING = "pending"
  ROUTING_ROUTED = "routed"
  ROUTING_UNMATCHED = "unmatched"
  ROUTING_FAILED = "failed"
  ROUTING_STATES = [ ROUTING_PENDING, ROUTING_ROUTED, ROUTING_UNMATCHED, ROUTING_FAILED ].freeze

  belongs_to :workspace
  belongs_to :alert_source
  belongs_to :incident, optional: true
  belongs_to :alert_group, optional: true
  belongs_to :matched_policy_rule, class_name: "PolicyRule", optional: true

  # Uniqueness of (alert_source_id, external_id) is enforced by the DB index.
  # The ingest path relies on RecordNotUnique as its idempotency check.
  validates :external_id, presence: true
  validates :fingerprint, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :routing_state, inclusion: { in: ROUTING_STATES }

  scope :open_status, -> { where(status: STATUS_FIRING) }

  # The alert listing the settings page and MCP search share: newest first,
  # with everything the row needs preloaded. Filters chain on top.
  scope :listing, -> { includes(:alert_source, :incident, matched_policy_rule: :policy).order(last_seen_at: :desc) }
  scope :from_source, ->(source) { where(alert_source: source) }
  scope :matched_by, ->(rule_id) { where(matched_policy_rule_id: rule_id) }
  scope :seen_since, ->(time) { where(last_seen_at: time..) }
  scope :pending_routing, -> { where(routing_state: ROUTING_PENDING) }

  def self.fallback_fingerprint(source, fields)
    values = source.fingerprint_fields.map { |field| fields[field].to_s }
    Digest::SHA256.hexdigest([ source.id, *values ].join("\n"))
  end

  def title
    fields["title"].presence || "Alert from #{alert_source.name}"
  end

  def firing?
    status == STATUS_FIRING
  end

  # One atomic UPDATE so concurrent firings never lose event_count increments.
  def record_firing!(now = Time.current)
    self.class.where(id: id).update_all([
      "event_count = event_count + 1, last_seen_at = ?, status = ?, resolved_at = NULL, updated_at = ?",
      now, STATUS_FIRING, Time.current
    ])
    reload
  end

  def resolve!(now = Time.current)
    update!(status: STATUS_RESOLVED, resolved_at: now, last_seen_at: now)
  end

  # The routing episode. These columns move together, so the alert owns the
  # moves and `pending` keeps one meaning: nothing has been applied yet.

  MAX_ROUTING_ATTEMPTS = 10

  def reset_routing!
    update!(incident: nil, alert_group: nil, matched_policy_rule: nil,
            channel_id: nil, channel_message_id: nil, last_notified_at: nil,
            routing_state: ROUTING_PENDING, routing_attempts: 0, routed_at: nil)
  end

  def mark_routed!(rule)
    update!(routing_state: ROUTING_ROUTED, routed_at: Time.current, matched_policy_rule: rule)
  end

  def mark_unmatched!
    update!(routing_state: ROUTING_UNMATCHED, routed_at: Time.current)
  end

  # Written outside the routing transaction, which has rolled back, so the
  # attempt count survives for the sweep to read.
  def record_routing_failure!
    attempts = routing_attempts + 1
    state = attempts >= MAX_ROUTING_ATTEMPTS ? ROUTING_FAILED : ROUTING_PENDING
    update_columns(routing_attempts: attempts, routing_state: state, updated_at: Time.current)
  end
end
