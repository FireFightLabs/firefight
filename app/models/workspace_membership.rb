class WorkspaceMembership < ApplicationRecord
  # Enums - Use strings for better readability
  enum :role, { member: "member", admin: "admin", owner: "owner" }, suffix: true

  # Associations
  belongs_to :user
  belongs_to :workspace

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
