class Policy < ApplicationRecord
  include Policy::Evaluation

  DOMAIN_ALERT_ROUTING = "alert_routing"
  DOMAIN_AUTO_INVESTIGATE = "auto_investigate"
  DOMAINS = [ DOMAIN_ALERT_ROUTING, DOMAIN_AUTO_INVESTIGATE ].freeze

  belongs_to :workspace
  has_many :policy_rules, dependent: :destroy

  validates :domain, presence: true, inclusion: { in: DOMAINS }
  validates :name, presence: true, uniqueness: { scope: [ :workspace_id, :domain ] }

  scope :enabled, -> { where(enabled: true) }
  scope :for_domain, ->(domain) { where(domain: domain) }

  def ordered_rules
    policy_rules.order(:priority)
  end
end
