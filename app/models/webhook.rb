class Webhook < ApplicationRecord
  PERMITTED_SCHEMES = %w[ http https ].freeze

  # Raised when test_blocked_reason refuses. Carries the sentence the surface
  # shows, so a caller renders it without restating the rule.
  class TestBlocked < StandardError; end

  # The one registry for what a customer may subscribe to and what payload
  # each event renders. Adding an event here (plus its jbuilder template and
  # the webhook-events.ts mirror) is the whole job.
  SUBSCRIBABLE_EVENT_TEMPLATES = {
    IncidentEvent::INCIDENT_CREATED => "webhooks/events/incident_created",
    IncidentEvent::INCIDENT_UPDATED => "webhooks/events/incident_updated",
    IncidentEvent::INCIDENT_ACCEPTED => "webhooks/events/incident_updated",
    IncidentEvent::INCIDENT_RESOLVED => "webhooks/events/incident_resolved",
    IncidentEvent::INCIDENT_REOPENED => "webhooks/events/incident_reopened",
    IncidentEvent::INCIDENT_CANCELED => "webhooks/events/incident_canceled",
    IncidentEvent::INCIDENT_ESCALATED => "webhooks/events/incident_escalated",
    IncidentEvent::LEAD_ASSIGNED => "webhooks/events/lead_assigned",
    IncidentEvent::ROLE_ASSIGNED => "webhooks/events/role_assigned",
    IncidentEvent::ROLE_UNASSIGNED => "webhooks/events/role_assigned",
    IncidentEvent::ACTION_CREATED => "webhooks/events/action_created",
    IncidentEvent::ACTION_PICKED_UP => "webhooks/events/action_picked_up",
    IncidentEvent::ACTION_COMPLETED => "webhooks/events/action_completed",
    IncidentEvent::ACTION_REASSIGNED => "webhooks/events/action_reassigned",
    IncidentEvent::RUNBOOK_ATTACHED => "webhooks/events/runbook_attached",
    IncidentEvent::POSTMORTEM_GENERATED => "webhooks/events/postmortem_generated",
    IncidentEvent::POSTMORTEM_EDITED => "webhooks/events/postmortem_edited",
    IncidentEvent::RELATIONSHIP_CREATED => "webhooks/events/relationship_created",
    IncidentEvent::MARKED_DUPLICATE => "webhooks/events/marked_duplicate",
    IncidentEvent::MERGED_INTO => "webhooks/events/merged_into",
    IncidentEvent::MILESTONE_NOTED => "webhooks/events/milestone_noted"
  }.freeze

  SUBSCRIBABLE_EVENTS = SUBSCRIBABLE_EVENT_TEMPLATES.keys.freeze

  has_secure_token :signing_secret, length: 32

  belongs_to :workspace
  has_many :webhook_deliveries, dependent: :destroy
  has_one :webhook_delinquency_tracker, dependent: :destroy

  after_create :create_webhook_delinquency_tracker!

  normalizes :subscribed_events, with: ->(value) { Array.wrap(value).map(&:to_s).uniq & SUBSCRIBABLE_EVENTS }
  normalizes :url, with: ->(value) { value.strip }

  validates :name, presence: true
  validate :validate_url

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(name: :asc, id: :desc) }
  scope :triggered_by, ->(event_type) { active.where("subscribed_events @> ?", [ event_type ].to_json) }

  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end

  # The newest event in the workspace this webhook subscribes to. Narrowing to
  # subscribed events before picking the newest finds one whenever any exists.
  # Picking the newest incident first and only then looking for a subscribed
  # event inside it finds nothing whenever the latest workspace activity is an
  # event type the webhook ignores.
  def latest_subscribed_event
    IncidentEvent.joins(:incident)
      .where(incidents: { workspace_id: workspace_id })
      .where(event_type: subscribed_events)
      .order(created_at: :desc)
      .first
  end

  # Why a test delivery cannot be sent right now, as a sentence, or nil. The
  # dashboard shows it as a flash and the MCP tool returns it as the error, so
  # the rule is written once.
  def test_blocked_reason
    return if latest_subscribed_event

    "No matching events found to test with. Nothing this webhook subscribes to has happened in this workspace yet."
  end

  # Queues one delivery of the newest subscribed event against this endpoint,
  # signed and sent the way a live delivery is. Raises when test_blocked_reason
  # refuses, so a caller that skipped the pre-check still cannot queue nothing.
  def queue_test_delivery!
    reason = test_blocked_reason
    raise TestBlocked, reason if reason

    event = latest_subscribed_event
    webhook_deliveries.create!(incident_event: event, event_type: event.event_type)
  end

  private

  def validate_url
    uri = URI.parse(url.presence.to_s)

    if PERMITTED_SCHEMES.exclude?(uri.scheme)
      errors.add :url, "must use http or https"
    end
  rescue URI::InvalidURIError
    errors.add :url, "is not a valid URL"
  end
end
