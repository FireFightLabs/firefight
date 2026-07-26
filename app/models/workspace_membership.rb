class WorkspaceMembership < ApplicationRecord
  include Principal

  # Enums - Use strings for better readability
  enum :role, { member: "member", admin: "admin", owner: "owner" }, suffix: true

  # Associations
  belongs_to :user
  belongs_to :workspace
  # A departed member's personal tokens die with the membership.
  has_many :personal_api_keys, class_name: "ApiKey", foreign_key: :workspace_membership_id,
           dependent: :destroy, inverse_of: :on_behalf_of

  # Encryptions
  encrypts :access_token, :refresh_token, deterministic: false

  # Validations
  validates :platform_user_id, presence: true
  validates :platform_user_id, uniqueness: { scope: :workspace_id }
  validates :role, presence: true

  # Delegations
  delegate :email, to: :user

  def display_name
    user.name
  end

  # Actor interface (shared with ApiKey) for polymorphic event/snapshot attribution.
  def actor_display_name = display_name
  def actor_kind = "user"

  def admin_access?
    admin_role? || owner_role?
  end

  # Member-level authority: humans read everything in their workspace;
  # admins additionally hold every system write — mirroring the settings
  # rule (mutations are admin territory). Personal tokens and OAuth
  # connections inherit exactly this, so an admin's agent can write config
  # with the admin's authority, still ledgered and approval-gated.
  # Admins hold every catalogued ability, including the tools an integration
  # mints: enabling a capability on a connection is itself the deliberate
  # decision, so it takes effect without a second grant step. Approval
  # policies still gate the risky ones. Members read Firefight's own data;
  # anything reaching another system stays an explicit grant for them, as it
  # does for API keys and agents.
  def implicitly_allowed?(action)
    return true if admin_access?

    action.system? && action.risk_level == Ability::Action::RISK_READ
  end

  def implicit_authority
    admin_access? ? :admin : :member
  end

  # Scopes
  scope :by_role, ->(role) { where(role: role) }
  scope :owners, -> { where(role: :owner) }
  scope :admins, -> { where(role: :admin) }
  scope :members, -> { where(role: :member) }

  # Class Methods
  def self.find_or_create_from_omniauth!(user, workspace, auth_hash)
    # Check if this is the first member (should be owner)
    is_first_member = workspace.workspace_memberships.empty?

    find_or_create_by!(
      user: user,
      workspace: workspace
    ) do |membership|
      membership.platform_user_id = auth_hash.uid
      membership.role = is_first_member ? :owner : :member
      membership.platform_data = auth_hash.extra.user_info
      membership.access_token = auth_hash.credentials.token
      membership.refresh_token = auth_hash.credentials.refresh_token if auth_hash.credentials.refresh_token
      membership.token_expires_at = Time.at(auth_hash.credentials.expires_at) if auth_hash.credentials.expires_at
      membership.joined_at = Time.current
    end
  end
end
