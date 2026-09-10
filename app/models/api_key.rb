class ApiKey < ApplicationRecord
  include Principal

  TOKEN_PREFIX = "ff_"
  TOKEN_LENGTH = 36
  CACHE_TTL = 24.hours
  CACHE_PREFIX = "api_key/auth/"

  belongs_to :workspace
  belongs_to :created_by, class_name: "WorkspaceMembership"
  # Set on a personal token, nil on a service key.
  belongs_to :on_behalf_of, class_name: "WorkspaceMembership",
             foreign_key: :workspace_membership_id, optional: true, inverse_of: :personal_api_keys
  # The token rotates, the agent does not, so grants and the ledger stay
  # attached across a rotation.
  belongs_to :agent, optional: true, inverse_of: :api_keys

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validate :on_behalf_of_same_workspace
  validate :one_identity_only

  after_update :invalidate_cache!
  after_destroy :invalidate_cache!

  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :service, -> { where(workspace_membership_id: nil, agent_id: nil) }
  scope :for_agents, -> { where.not(agent_id: nil) }

  def self.generate_token
    "#{TOKEN_PREFIX}#{SecureRandom.base58(TOKEN_LENGTH)}"
  end

  def self.digest_token(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    digest = digest_token(raw_token)
    api_key = Rails.cache.fetch("#{CACHE_PREFIX}#{digest}", expires_in: CACHE_TTL) do
      find_by(token_digest: digest)
    end

    return nil unless api_key
    return nil unless api_key.active? && !api_key.deleted? && !api_key.expired?

    api_key
  end

  def self.create_with_token!(attributes)
    raw_token = generate_token
    api_key = create!(
      **attributes,
      token_digest: digest_token(raw_token),
      token_prefix: raw_token.first(12)
    )
    [ api_key, raw_token ]
  end

  def live?
    active? && !deleted? && !expired?
  end

  def personal?
    workspace_membership_id.present?
  end

  def service?
    !personal?
  end

  # An agent's token acts as the agent, a personal token as the person, a
  # service key as itself.
  def principal
    agent || on_behalf_of || self
  end

  def mcp_readable?(resource)
    has_permission?(resource, Ability::Action::ACTION_READ)
  end

  # A personal token carries the member's authority exactly, so the rule
  # lives on the membership rather than being restated here.
  def has_permission?(resource, action)
    return on_behalf_of.implicitly_permits?(resource, action) if personal?

    Ability::Resolver.resolve(self).covers?(Ability::Action.system_key(resource, action))
  end

  # Derived from the grants rather than stored, so there is no second copy to
  # drift. Expired grants are included, lapsing is the Permissions screen's business.
  def granted_permissions
    ability_grants.includes(:action).each_with_object({}) do |grant, matrix|
      key = grant.action&.key
      next unless key && Ability::Action.grantable_keys.include?(key)

      resource, action = key.split(".")
      (matrix[resource] ||= []) << action
    end
  end

  # Tool actions from integrations are outside the matrix and left alone.
  def replace_permissions!(matrix)
    Ability::Grant.replace_system_grants!(principal: self, workspace: workspace, matrix: matrix)
  end

  def touch_last_used!
    return if last_used_at.present? && last_used_at > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  # Actor interface shared with WorkspaceMembership. No platform_user_id,
  # a key is not a person to DM.
  def actor_display_name = name
  def actor_kind = Ability::Principal::KIND_API_KEY
  def platform_user_id = nil

  # Both set would make principal silently pick one.
  def one_identity_only
    return if workspace_membership_id.blank? || agent_id.blank?

    errors.add(:agent, "cannot be set on a personal token")
  end

  def activate!
    update!(active: true)
  end

  def deactivate!
    update!(active: false)
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def invalidate_cache!
    Rails.cache.delete("#{CACHE_PREFIX}#{token_digest}")
  end

  private

  def on_behalf_of_same_workspace
    return if on_behalf_of.nil? || on_behalf_of.workspace_id == workspace_id

    errors.add(:on_behalf_of, "must belong to the same workspace")
  end
end
