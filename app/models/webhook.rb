class Webhook < ApplicationRecord
  PERMITTED_SCHEMES = %w[ http https ].freeze

  SUBSCRIBABLE_EVENTS = [
    IncidentEvent::INCIDENT_CREATED,
    IncidentEvent::INCIDENT_UPDATED,
    IncidentEvent::INCIDENT_ACCEPTED,
    IncidentEvent::INCIDENT_RESOLVED,
    IncidentEvent::INCIDENT_REOPENED,
    IncidentEvent::INCIDENT_ESCALATED,
    IncidentEvent::LEAD_ASSIGNED,
    IncidentEvent::ACTION_CREATED,
    IncidentEvent::ACTION_PICKED_UP,
    IncidentEvent::ACTION_COMPLETED,
    IncidentEvent::POSTMORTEM_GENERATED,
    IncidentEvent::RELATIONSHIP_CREATED,
    IncidentEvent::MARKED_DUPLICATE,
    IncidentEvent::MERGED_INTO
  ].freeze

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
