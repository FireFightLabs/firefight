class Policy < ApplicationRecord
  include Policy::Evaluation

  DOMAIN_ALERT_ROUTING = "alert_routing"
  DOMAIN_AUTO_INVESTIGATE = "auto_investigate"
  DOMAIN_APPROVALS = "approvals"
  DOMAINS = [ DOMAIN_ALERT_ROUTING, DOMAIN_AUTO_INVESTIGATE, DOMAIN_APPROVALS ].freeze

  DEFAULT_ALERT_ROUTING_NAME = "Alert routing".freeze
  DEFAULT_APPROVALS_NAME = "Approvals".freeze

  belongs_to :workspace
  belongs_to :scoped_to, polymorphic: true, optional: true
  has_many :policy_rules, dependent: :destroy

  include Policy::AlertRoutingConfig

  validates :domain, presence: true, inclusion: { in: DOMAINS }
  validates :name, presence: true,
                   uniqueness: { scope: [ :workspace_id, :domain, :scoped_to_type, :scoped_to_id ] }
  validate :scoped_to_same_workspace

  scope :enabled, -> { where(enabled: true) }
  scope :for_domain, ->(domain) { where(domain: domain) }
  scope :workspace_wide, -> { where(scoped_to_type: nil) }

  def ordered_rules
    policy_rules.order(:priority)
  end

  private

  def scoped_to_same_workspace
    return unless scoped_to.respond_to?(:workspace_id)
    return if scoped_to.workspace_id == workspace_id

    errors.add(:scoped_to, "must belong to the same workspace")
  end
end
