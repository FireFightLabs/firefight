class Policy < ApplicationRecord
  include Policy::Evaluation

  DOMAIN_ALERT_ROUTING = "alert_routing"
  DOMAIN_AUTO_INVESTIGATE = "auto_investigate"
  DOMAINS = [ DOMAIN_ALERT_ROUTING, DOMAIN_AUTO_INVESTIGATE ].freeze

  DEFAULT_ALERT_ROUTING_NAME = "Alert routing".freeze

  belongs_to :workspace
  belongs_to :scoped_to, polymorphic: true, optional: true
  has_many :policy_rules, dependent: :destroy

  validates :domain, presence: true, inclusion: { in: DOMAINS }
  validates :name, presence: true,
                   uniqueness: { scope: [ :workspace_id, :domain, :scoped_to_type, :scoped_to_id ] }
  validate :scoped_to_same_workspace
  validate :alert_routing_domain_config

  scope :enabled, -> { where(enabled: true) }
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :workspace_wide, -> { where(scoped_to_type: nil) }

  def ordered_rules
    policy_rules.order(:priority)
  end

  private

  # Grouping knobs live in domain_config for the alert_routing domain; validate
  # them at write time so ingest never has to defend against nonsense values.
  def alert_routing_domain_config
    return unless domain == DOMAIN_ALERT_ROUTING && domain_config.present?

    window = domain_config["grouping_window_minutes"]
    if window.present? && !AlertGroup::WINDOW_MINUTES_RANGE.cover?(window.to_i)
      errors.add(:domain_config, "grouping window must be between 5 minutes and 7 days")
    end

    fields = domain_config["content_match_fields"]
    if fields.present? && (!fields.is_a?(Array) || fields.any? { |f| !f.is_a?(String) || f.strip.empty? })
      errors.add(:domain_config, "content match fields must be a list of field names")
    end
  end

  def scoped_to_same_workspace
    return unless scoped_to.respond_to?(:workspace_id)
    return if scoped_to.workspace_id == workspace_id

    errors.add(:scoped_to, "must belong to the same workspace")
  end
end
