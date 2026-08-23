class WorkspaceMembership < ApplicationRecord
  include Principal

  # Strings, not integers, so a raw row reads without a lookup table.
  enum :role, { member: "member", admin: "admin", owner: "owner" }, suffix: true

  belongs_to :user
  belongs_to :workspace
  # A departed member's personal tokens die with the membership.
  has_many :personal_api_keys, class_name: "ApiKey", foreign_key: :workspace_membership_id,
           dependent: :destroy, inverse_of: :on_behalf_of


  validates :platform_user_id, presence: true
  validates :platform_user_id, uniqueness: { scope: :workspace_id }
  validates :role, presence: true

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

  # Incident participation is member-level authority. Responding to an
  # incident is what a member is for, so declaring, updating, closing and
  # staffing one needs no grant, and it must read the same whether the
  # member is clicking a button in Slack, calling the API with a personal
  # token, or driving MCP. Configuring the workspace stays admin territory.
  PARTICIPATION = { ApiKey::RESOURCE_INCIDENTS => [ ApiKey::ACTION_CREATE, ApiKey::ACTION_UPDATE ].freeze }.freeze

  # Member-level authority: humans read everything in their workspace and
  # participate in incidents. Admins additionally hold every system write,
  # mirroring the settings rule (mutations are admin territory). Personal
  # tokens and OAuth connections inherit exactly this, so an admin's agent
  # can write config with the admin's authority, still ledgered and
  # approval-gated. Admins hold every catalogued ability, including the tools
  # an integration mints. Enabling a capability on a connection is itself the
  # deliberate decision, so it takes effect without a second grant step.
  # Approval policies still gate the risky ones. Anything reaching another
  # system stays an explicit grant for members, as it does for API keys and
  # agents.
  def implicitly_allowed?(action)
    return true if admin_access?
    return false unless action.system?

    implicitly_permits?(*action.key.split("."))
  end

  # The same rule expressed over a resource/action pair, for callers holding
  # those rather than an Ability::Action. ApiKey's personal-token path reads
  # it, so the two can never drift.
  def implicitly_permits?(resource, crud_action)
    return true if admin_access?
    return true if crud_action.to_s == ApiKey::ACTION_READ

    PARTICIPATION.fetch(resource, []).include?(crud_action.to_s)
  end

  def implicit_authority
    admin_access? ? :admin : :member
  end

  scope :by_role, ->(role) { where(role: role) }
  scope :owners, -> { where(role: :owner) }
  scope :admins, -> { where(role: :admin) }
  scope :members, -> { where(role: :member) }

  # Finds a member from whatever identifier a caller holds. Email is the one
  # people can type and the one that survives a platform move, so it is what
  # machine-facing surfaces ask for. ids are accepted because our own pickers
  # and API reads hand them back. Resolves only, never provisions. Creating a
  # member is a billable act and belongs to a deliberate flow, not to a write
  # that happens to name someone.
  def self.resolve(reference)
    return nil if reference.blank?

    reference = reference.to_s
    find_by(id: reference) ||
      find_by(platform_user_id: reference) ||
      joins(:user).find_by(users: { email: reference.downcase })
  end

  # Locks the workspace so "am I the first member" and the insert that answers
  # it are one serialized step. Two people completing the install in the same
  # moment would otherwise both read an empty workspace and both become owner,
  # which hands workspace administration to whoever happened to race.
  def self.find_or_create_from_omniauth!(user, workspace, auth_hash)
    transaction do
      # Locks a separate instance on purpose. workspace.with_lock reloads, and
      # reload clears previously_new_record?, which the install flow reads
      # afterwards to decide whether to seed a brand new workspace.
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
