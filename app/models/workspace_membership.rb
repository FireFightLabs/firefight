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

  # Responding to an incident, tidying your own chats and teaching Halon what you know need no grant on any surface.
  # Configuring the workspace stays admin territory.
  PARTICIPATION = {
    Ability::Action::RESOURCE_INCIDENTS => [ Ability::Action::ACTION_CREATE, Ability::Action::ACTION_UPDATE ].freeze,
    Ability::Action::RESOURCE_CHATS => [ Ability::Action::ACTION_UPDATE, Ability::Action::ACTION_DELETE ].freeze,
    Ability::Action::RESOURCE_MEMORY => [ Ability::Action::ACTION_CREATE, Ability::Action::ACTION_UPDATE ].freeze
  }.freeze

  # Held in every environment without a grant, until an admin grants one to the member, alone or in a set. From then the
  # grants decide where, so a grant narrows the default rather than adding to it, and one that expires narrows to nothing.
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
  DefaultAccess = Data.define(:action, :state, :grant) do
    def note = DEFAULT_NOTES.fetch(state)
  end

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

    key = Ability::Action.system_key(resource, crud_action)
    return !Ability::Resolver.resolve(self, workspace_id).granted_ever?(key) if NARROWABLE_KEYS.include?(key)
    return true if crud_action.to_s == Ability::Action::ACTION_READ

    PARTICIPATION.fetch(resource, []).include?(crud_action.to_s)
  end

  def implicit_authority
    admin_access? ? :admin : :member
  end

  # Where each default stands for this member, which the Permissions screen shows and lets an admin take away.
  def default_access
    return [] if admin_access?

    resolved = Ability::Resolver.resolve(self, workspace_id)
    withheld = ability_grants.where(workspace_id: workspace_id).includes(:action).select(&:no_access?).index_by { |grant| grant.action.key }
    NARROWABLE_KEYS.map do |key|
      state = if withheld.key?(key) then DEFAULT_NO_ACCESS
              elsif resolved.granted_ever?(key) then DEFAULT_NARROWED
              else DEFAULT_HELD
              end
      DefaultAccess.new(action: Ability::Action.system!(key), state: state, grant: withheld[key])
    end
  end

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
