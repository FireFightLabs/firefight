class WorkspaceMembership < ApplicationRecord
  include Principal

  # Strings, not integers, so a raw row reads without a lookup table.
  enum :role, { member: "member", admin: "admin", owner: "owner" }, suffix: true

  belongs_to :user
  belongs_to :workspace
  # A departed member's personal tokens die with the membership.
  has_many :investigation_verdicts, class_name: "Investigation::Verdict", foreign_key: :member_id,
           dependent: :destroy, inverse_of: :member
  has_many :personal_api_keys, class_name: "ApiKey", foreign_key: :workspace_membership_id,
           dependent: :destroy, inverse_of: :on_behalf_of
  # Same for OAuth connections resolving to the member.
  has_many :oauth_access_grants, class_name: "Doorkeeper::AccessGrant",
           foreign_key: :resource_owner_id, dependent: :delete_all
  has_many :oauth_access_tokens, class_name: "Doorkeeper::AccessToken",
           foreign_key: :resource_owner_id, dependent: :delete_all

  # Nil for a teammate who joined by email and has not used the chat platform here yet.
  validates :platform_user_id, uniqueness: { scope: :workspace_id }, allow_nil: true
  validates :user_id, uniqueness: { scope: :workspace_id }
  validates :role, presence: true

  delegate :email, to: :user

  def display_name
    user.name
  end

  # Fills in who this member is on the chat platform the first time they show up there. One already known is kept,
  # so a second account in the same team never takes over the seat.
  def link_platform_user!(platform_user_id, platform_data = nil)
    return self if platform_user_id.blank? || self.platform_user_id.present?

    update!(platform_user_id: platform_user_id, platform_data: platform_data.presence || self.platform_data)
    self
  end

  # Actor interface shared with ApiKey.
  def actor_display_name = display_name
  def actor_kind = Ability::Principal::KIND_USER

  def admin_access?
    admin_role? || owner_role?
  end

  # Responding to an incident, tidying your own chats and teaching Halon what you know need no grant on any surface.
  # Configuring the workspace stays admin territory.
  PARTICIPATION = {
    Ability::Action::RESOURCE_INCIDENTS => [ Ability::Action::ACTION_CREATE, Ability::Action::ACTION_UPDATE ].freeze,
    Ability::Action::RESOURCE_CHATS => [ Ability::Action::ACTION_UPDATE, Ability::Action::ACTION_DELETE ].freeze,
    Ability::Action::RESOURCE_MEMORY => [ Ability::Action::ACTION_CREATE, Ability::Action::ACTION_UPDATE ].freeze
  }.freeze

  # Held in every environment without a grant, until an admin grants one to the member, alone or in a set. From then the
  # grants decide where, so a grant narrows the default rather than adding to it, and one that expires narrows to nothing.
  # A connected tool that only reads is held the same way (default_read?).
  NARROWABLE_KEYS = [ Ability::Action::MAP_READ, Ability::Action::INVESTIGATIONS_CREATE ].freeze

  # Where one of those defaults stands for a member: held, narrowed by a grant, or taken away by an admin.
  DEFAULT_HELD = "held"
  DEFAULT_NARROWED = "narrowed"
  DEFAULT_NO_ACCESS = "no_access"
  DEFAULT_NOTES = {
    DEFAULT_HELD => "Every member has this without a grant.",
    DEFAULT_NARROWED => "A grant below decides where they have it.",
    DEFAULT_NO_ACCESS => "No access. Restore it to give them the default back."
  }.freeze
  # One of the defaults, either a system action or a connection's read pack, which stands for every tool on it that reads.
  DefaultAccess = Data.define(:action, :role, :state, :grant) do
    def note = DEFAULT_NOTES.fetch(state)
  end

  # Admins hold every catalogued ability including integration tools. A member reads every connected tool that only
  # reads, the way they read Firefight's own data, while a tool that changes something stays an explicit grant.
  def implicitly_allowed?(action, resolved = nil)
    return true if admin_access?
    return default_read?(action, resolved) if action.tool?

    implicitly_permits?(*action.key.split("."), resolved)
  end

  # The same rule for callers holding a resource and action rather than an
  # Ability::Action. ApiKey's personal-token path reads it. resolved is the member's grants when the caller already has them.
  def implicitly_permits?(resource, crud_action, resolved = nil)
    return true if admin_access?
    return false if Ability::Action::ADMIN_ONLY_RESOURCES.include?(resource.to_s)

    key = Ability::Action.system_key(resource, crud_action)
    return !(resolved || Ability::Resolver.resolve(self, workspace_id)).granted_ever?(key) if NARROWABLE_KEYS.include?(key)
    return true if crud_action.to_s == Ability::Action::ACTION_READ

    PARTICIPATION.fetch(resource, []).include?(crud_action.to_s)
  end

  # A connected tool that only reads, held until a grant of it, alone or in a set such as its connection's read pack,
  # narrows it.
  def default_read?(action, resolved = nil)
    return false unless action.tool? && action.read? && action.workspace_id == workspace_id

    !(resolved || Ability::Resolver.resolve(self, workspace_id)).granted_ever?(action.key)
  end

  # Whether an admin may take this away from a member with No access: a default above, or a connection's read pack.
  def self.default_target?(action: nil, role: nil)
    return role.read_pack? if role

    action.present? && (NARROWABLE_KEYS.include?(action.key) || (action.tool? && action.read?))
  end

  def implicit_authority
    admin_access? ? Principal::IMPLICIT_ADMIN : Principal::IMPLICIT_MEMBER
  end

  # Explains implicitly_allowed? on the Permissions screen. Change the two together.
  IMPLICIT_AUTHORITY_NOTES = {
    Principal::IMPLICIT_ADMIN =>
      "Admins hold every catalogued ability without a grant, every connected tool included. Approval policies still gate " \
      "the risky ones.",
    Principal::IMPLICIT_MEMBER =>
      "Members read Firefight's own data, including the resource map in every environment, read every connected tool, " \
      "take part in incidents, and ask Halon or start investigations without a grant, whether from Slack, the dashboard, " \
      "the API, or MCP. A grant of map.read limits the map to the environments it names, a grant of investigations.create " \
      "decides who may ask, and a grant of a connection's reads, alone or in a pack, decides where they read it. No access " \
      "below takes any of these away at once, and Restore gives it back. Configuring the workspace and any tool that " \
      "changes something needs one of the grants below, such as a connection's changes pack."
  }.freeze

  def implicit_authority_note = IMPLICIT_AUTHORITY_NOTES.fetch(implicit_authority)

  # Where each default stands for this member, which the Permissions screen shows and lets an admin take away. A
  # connection's reads are one row, its read pack, rather than a row for each tool.
  def default_access
    return [] if admin_access?

    resolved = Ability::Resolver.resolve(self, workspace_id)
    grants = ability_grants.loaded? ? ability_grants : ability_grants.includes(:action, :role)
    withheld = grants.select { |grant| grant.workspace_id == workspace_id && grant.no_access? }
    by_action = withheld.select(&:action).index_by { |grant| grant.action.key }
    by_role = withheld.select(&:role).index_by(&:role_id)
    system = NARROWABLE_KEYS.map do |key|
      DefaultAccess.new(action: Ability::Action.system!(key), role: nil, state: default_state(key, by_action, resolved), grant: by_action[key])
    end
    system + read_packs.map do |pack|
      DefaultAccess.new(action: nil, role: pack, state: pack_state(pack, by_role, resolved), grant: by_role[pack.id])
    end
  end

  def default_state(key, withheld, resolved)
    return DEFAULT_NO_ACCESS if withheld.key?(key)

    resolved.granted_ever?(key) ? DEFAULT_NARROWED : DEFAULT_HELD
  end
  private :default_state

  def pack_state(pack, withheld, resolved)
    return DEFAULT_NO_ACCESS if withheld.key?(pack.id)

    pack.actions.any? { |action| resolved.granted_ever?(action.key) } ? DEFAULT_NARROWED : DEFAULT_HELD
  end
  private :pack_state

  # Every connection's read pack that holds a tool. A listing of every member sets it once for all of them.
  def self.read_packs_of(workspace)
    workspace.ability_roles.where(pack: Ability::Role::PACK_READ).joins(:integration).merge(Integration.where(deleted_at: nil))
             .includes(:actions, :integration).order(:name).select { |pack| pack.actions.any? }
  end

  attr_writer :read_packs

  def read_packs = @read_packs ||= self.class.read_packs_of(workspace)
  private :read_packs

  scope :by_role, ->(role) { where(role: role) }
  scope :owners, -> { where(role: :owner) }
  scope :admins, -> { where(role: :admin) }
  scope :members, -> { where(role: :member) }

  # Never provisions, creating a member is billable and belongs to a deliberate flow.
  # Whoever is acting, so a person can say "make me the lead" without giving their own email.
  ME = "me".freeze

  # acting is who asked. A machine acting is not a person and has no seat in an incident.
  def self.resolve(reference, acting: nil)
    return nil if reference.blank?

    reference = reference.to_s
    return (acting if acting.is_a?(WorkspaceMembership)) if reference.casecmp?(ME)

    find_by(id: reference) ||
      find_by(platform_user_id: reference) ||
      joins(:user).find_by(users: { email: reference.downcase })
  end

  # A reference matching nobody raises. A blank reference means nobody and
  # resolves to nil.
  def self.resolve!(reference, acting: nil)
    return nil if reference.blank?

    resolve(reference, acting: acting) || raise(ActiveRecord::RecordNotFound, unresolved(reference, acting))
  end

  def self.unresolved(reference, acting)
    return "\"me\" is not a person here, since #{acting.principal_label} is acting" if reference.to_s.casecmp?(ME) && acting

    "No workspace member matches #{reference.inspect}"
  end
  private_class_method :unresolved

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

  # A member who joined before the workspace connected Slack keeps their row and gains their platform id.
  def self.create_from_omniauth!(user, workspace, auth_hash)
    is_first_member = workspace.workspace_memberships.empty?

    membership = find_or_create_by!(
      user: user,
      workspace: workspace
    ) do |created|
      created.platform_user_id = auth_hash.uid
      created.role = is_first_member ? :owner : :member
      created.platform_data = auth_hash.extra.user_info
      created.joined_at = Time.current
    end
    membership.link_platform_user!(auth_hash.uid, auth_hash.extra.user_info)
  end
end
