class ApiKey < ApplicationRecord
  include Principal

  TOKEN_PREFIX = "ff_"
  TOKEN_LENGTH = 36
  CACHE_TTL = 24.hours
  CACHE_PREFIX = "api_key/auth/"

  # Resources
  RESOURCE_INCIDENTS = "incidents"
  RESOURCE_SEVERITIES = "severities"
  RESOURCE_STATUSES = "statuses"
  RESOURCE_INCIDENT_TYPES = "incident_types"
  RESOURCE_CUSTOM_FIELDS = "custom_fields"
  # Which fields a responder is asked at each lifecycle moment. Separate from
  # custom_fields because defining a field and deciding that Name is required
  # on every declaration are different powers.
  RESOURCE_FORMS = "forms"
  RESOURCE_CATALOG = "catalog"
  RESOURCE_ALERTS = "alerts"
  RESOURCE_POLICIES = "policies"
  RESOURCE_RUNBOOKS = "runbooks"
  RESOURCE_APPROVALS = "approvals"

  RESOURCES = [
    RESOURCE_INCIDENTS, RESOURCE_SEVERITIES, RESOURCE_STATUSES, RESOURCE_INCIDENT_TYPES,
    RESOURCE_CUSTOM_FIELDS, RESOURCE_FORMS, RESOURCE_CATALOG, RESOURCE_ALERTS, RESOURCE_POLICIES,
    RESOURCE_RUNBOOKS, RESOURCE_APPROVALS
  ].freeze

  # Actions
  ACTION_READ = "read"
  ACTION_CREATE = "create"
  ACTION_UPDATE = "update"
  ACTION_DELETE = "delete"

  ACTIONS = [ ACTION_READ, ACTION_CREATE, ACTION_UPDATE, ACTION_DELETE ].freeze

  belongs_to :workspace
  belongs_to :created_by, class_name: "WorkspaceMembership"
  # Personal token: acts with this human's authority; nil = service key.
  belongs_to :on_behalf_of, class_name: "WorkspaceMembership",
             foreign_key: :workspace_membership_id, optional: true, inverse_of: :personal_api_keys


  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validate :on_behalf_of_same_workspace

  after_update :invalidate_cache!
  after_destroy :invalidate_cache!

  scope :active, -> { where(active: true, deleted_at: nil) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :service, -> { where(workspace_membership_id: nil) }

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

  def personal?
    workspace_membership_id.present?
  end

  def service?
    !personal?
  end

  # Who this request is authorized AS: the human behind a personal token,
  # or the key itself for a service key.
  def principal
    on_behalf_of || self
  end

  def mcp_readable?(resource)
    has_permission?(resource, ACTION_READ)
  end

  # Personal tokens carry the member's authority: read everything a member
  # sees, write only what an admin can (mirrors Principal#implicitly_allowed?).
  # Service keys resolve against their ability grants.
  def has_permission?(resource, action)
    return action.to_s == ACTION_READ || on_behalf_of.admin_access? if personal?

    Ability::Resolver.resolve(self).covers?(Ability::Action.system_key(resource, action))
  end

  # The permissions matrix, derived from the grants it edits rather than stored
  # alongside them. There is no second copy to drift out of step, and a grant
  # made on the Permissions screen shows up here ticked instead of being
  # silently reconciled away.
  #
  # Expired grants are included: the switch says what was granted, and when it
  # lapses is the Permissions screen's business.
  def granted_permissions
    ability_grants.includes(:action).each_with_object({}) do |grant, matrix|
      key = grant.action&.key
      next unless key && self.class.managed_ability_keys.include?(key)

      resource, action = key.split(".")
      (matrix[resource] ||= []) << action
    end
  end

  # Replaces this key's system-action grants with the matrix. Tool actions from
  # integrations are outside the matrix, so they are left alone.
  def replace_permissions!(matrix)
    desired = Array(matrix).flat_map do |resource, actions|
      Array(actions).map { |action| Ability::Action.system_key(resource, action) }
    end
    unknown = desired - self.class.managed_ability_keys
    raise ArgumentError, "unknown permission #{unknown.first}" if unknown.any?

    Ability::Grant.sync_direct!(
      principal: self, workspace: workspace,
      desired_keys: desired, managed_keys: self.class.managed_ability_keys
    )
  end

  def self.managed_ability_keys
    @managed_ability_keys ||= RESOURCES.product(ACTIONS).map do |resource, action|
      Ability::Action.system_key(resource, action)
    end.freeze
  end

  def touch_last_used!
    return if last_used_at.present? && last_used_at > 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  # Actor interface (shared with WorkspaceMembership) for polymorphic
  # event/snapshot attribution. API keys are integrations, not people, so
  # they have no platform_user_id (no Slack DM target).
  def actor_display_name = name
  def actor_kind = "api_key"
  def platform_user_id = nil

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
