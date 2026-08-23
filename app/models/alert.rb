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
end
