class WorkspaceMembership < ApplicationRecord
  include Principal

  # Strings, not integers, so a raw row reads without a lookup table.
  enum :role, { member: "member", admin: "admin", owner: "owner" }, suffix: true

  belongs_to :user
  belongs_to :workspace
  # A departed member's personal tokens die with the membership.
  has_many :personal_api_keys, class_name: "ApiKey", foreign_key: :workspace_membership_id,
           dependent: :destroy, inverse_of: :on_behalf_of
  # Same for OAuth connections resolving to the member.
  has_many :oauth_access_grants, class_name: "Doorkeeper::AccessGrant",
           foreign_key: :resource_owner_id, dependent: :delete_all
  has_many :oauth_access_tokens, class_name: "Doorkeeper::AccessToken",
           foreign_key: :resource_owner_id, dependent: :delete_all

  validates :platform_user_id, presence: true
  validates :platform_user_id, uniqueness: { scope: :workspace_id }
  validates :role, presence: true

  delegate :email, to: :user

  def display_name
    user.name
  end

  # Actor interface shared with ApiKey.
  def actor_display_name = display_name
  def actor_kind = Ability::Principal::KIND_USER

  def admin_access?
    admin_role? || owner_role?
  end

  # Responding to an incident needs no grant, from Slack, a personal token or
  # MCP alike. Configuring the workspace stays admin territory.
  PARTICIPATION = { Ability::Action::RESOURCE_INCIDENTS => [ Ability::Action::ACTION_CREATE, Ability::Action::ACTION_UPDATE ].freeze }.freeze

  # Admins hold every catalogued ability including integration tools, since enabling one on a
  # connection is already the deliberate step. For members anything reaching another system stays an explicit grant.
  def implicitly_allowed?(action)
    return true if admin_access?
    return false unless action.system?

    implicitly_permits?(*action.key.split("."))
  end

  # The same rule for callers holding a resource and action rather than an
  # Ability::Action. ApiKey's personal-token path reads it.
  def implicitly_permits?(resource, crud_action)
    return true if admin_access?
    return false if Ability::Action::ADMIN_ONLY_RESOURCES.include?(resource.to_s)
    return true if crud_action.to_s == Ability::Action::ACTION_READ

    PARTICIPATION.fetch(resource, []).include?(crud_action.to_s)
  end

  def implicit_authority
    admin_access? ? :admin : :member
  end

  scope :by_role, ->(role) { where(role: role) }
  scope :owners, -> { where(role: :owner) }
  scope :admins, -> { where(role: :admin) }
  scope :members, -> { where(role: :member) }

  # Never provisions, creating a member is billable and belongs to a deliberate flow.
  def self.resolve(reference)
    return nil if reference.blank?

    reference = reference.to_s
    find_by(id: reference) ||
      find_by(platform_user_id: reference) ||
      joins(:user).find_by(users: { email: reference.downcase })
  end

  # A reference matching nobody raises. A blank reference means nobody and
  # resolves to nil.
  def self.resolve!(reference)
    return nil if reference.blank?

    resolve(reference) ||
      raise(ActiveRecord::RecordNotFound, "No workspace member matches #{reference.inspect}")
  end

  # Locks the workspace so "am I the first member" and the insert are one
  # step. Two installs finishing at once would otherwise both become owner.
  def self.find_or_create_from_omniauth!(user, workspace, auth_hash)
    transaction do
      # A separate instance on purpose. with_lock reloads, which clears
      # previously_new_record? that the install flow reads afterwards.
      Workspace.lock.find(workspace.id)
      create_from_omniauth!(user, workspace, auth_hash)
    end
  end

  def self.create_from_omniauth!(user, workspace, auth_hash)
    is_first_member = workspace.workspace_memberships.empty?

    find_or_create_by!(
      user: user,
      workspace: workspace
    ) do |membership|
      membership.platform_user_id = auth_hash.uid
      membership.role = is_first_member ? :owner : :member
      membership.platform_data = auth_hash.extra.user_info
      membership.joined_at = Time.current
    end
  end
end
