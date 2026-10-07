# Permission sets Firefight keeps in step with the connections, so reaching a connection is one grant rather than a set
# someone has to remember to update when the provider adds a tool. Each connection has a read pack, a changes pack and
# an everything pack, and the workspace has one pack of every connection's tools that change something. A tool joins
# by its read-only flag, a renamed connection renames its packs, and a disconnected one takes its packs with it.
# Nobody edits or deletes a pack by hand. They are granted like any other set.
module Ability::Role::Packs
  extend ActiveSupport::Concern

  PACK_READ = "read"
  PACK_CHANGES = "changes"
  PACK_EVERYTHING = "everything"
  PACK_CHANGES_EVERYWHERE = "changes_everywhere"
  CONNECTION_PACKS = [ PACK_READ, PACK_CHANGES, PACK_EVERYTHING ].freeze
  PACKS = [ *CONNECTION_PACKS, PACK_CHANGES_EVERYWHERE ].freeze
  CHANGES_EVERYWHERE_NAME = "Changes everywhere".freeze

  included do
    belongs_to :integration, optional: true

    validates :pack, inclusion: { in: PACKS }, allow_nil: true
    validate :left_alone_by_hand, on: :update
    before_destroy :refuse_by_hand, prepend: true

    scope :built_in, -> { where.not(pack: nil) }
    scope :hand_made, -> { where(pack: nil) }
  end

  class_methods do
    # Brings a connection's packs in step with it, named after it and holding each of its tools' actions in the packs
    # its read-only flag puts it in. A disconnected connection's packs go, and its tools leave Changes everywhere.
    def keep_in_step!(integration)
      return retire!(integration) if integration.deleted?

      transaction do
        packs = packs_for!(integration)
        Ability::Action.where(source: integration.tools).find_each { |action| file(action, packs) }
      end
    end

    # Puts one tool's action in the packs its read-only flag says, and takes it out of the others.
    def file!(action, integration)
      return if integration.deleted?

      transaction { file(action, packs_for!(integration)) }
    end

    # The pack a member is told to ask for when a tool that changes something is refused, or nil.
    def to_ask_for(action)
      return unless action&.source.is_a?(Integration::Tool) && !action.read?

      find_by(integration_id: action.source.integration_id, pack: PACK_CHANGES)
    end

    private

    def file(action, packs)
      wanted = action.read? ? [ PACK_READ, PACK_EVERYTHING ] : [ PACK_CHANGES, PACK_EVERYTHING, PACK_CHANGES_EVERYWHERE ]
      packs.each { |pack, role| wanted.include?(pack) ? role.hold(action) : role.release(action) }
    end

    def retire!(integration)
      transaction do
        everywhere = integration.workspace.ability_roles.find_by(pack: PACK_CHANGES_EVERYWHERE, integration_id: nil)
        everywhere&.role_actions&.where(action_id: Ability::Action.where(source: integration.tools).select(:id))&.destroy_all
        where(integration_id: integration.id).find_each(&:retire!)
      end
    end

    # The connection's three packs and the workspace's Changes everywhere, by pack, made the first time and renamed
    # whenever the connection's name changed.
    def packs_for!(integration)
      workspace = integration.workspace
      packs = CONNECTION_PACKS.index_with { |pack| pack!(workspace, pack, integration) }
      packs.merge(PACK_CHANGES_EVERYWHERE => pack!(workspace, PACK_CHANGES_EVERYWHERE, nil))
    end

    # Another discovery may make the pack first, and the savepoint keeps the surrounding transaction usable when it does.
    def pack!(workspace, pack, integration)
      role = workspace.ability_roles.find_or_initialize_by(pack: pack, integration_id: integration&.id)
      role.slug ||= free_slug(workspace, integration ? "#{integration.slug}_#{pack}" : pack)
      role.assign_attributes(name: pack_name(pack, integration), description: pack_description(pack, integration))
      made = role.new_record?
      role.keep_in_step { transaction(requires_new: true) { role.save! } } if role.changed?
      grant_investigator(workspace, role) if made && pack == PACK_READ
      role
    rescue ActiveRecord::RecordNotUnique
      workspace.ability_roles.find_by!(pack: pack, integration_id: integration&.id)
    end

    # Investigations read what is connected, so the investigator is given each connection's reads the moment there are any.
    # It is an ordinary grant an admin revokes per connection, and nothing gives it back.
    def grant_investigator(workspace, role)
      workspace.ability_grants.find_or_create_by!(principal: SystemAgent.investigator, role: role)
    end

    # A hand-made set may already be called what a pack would be, so the pack takes the next free slug instead.
    def free_slug(workspace, base)
      taken = workspace.ability_roles.where("slug = :base OR slug LIKE :like", base: base, like: "#{sanitize_sql_like(base)}_%").pluck(:slug)
      return base unless taken.include?(base)

      (2..).lazy.map { |count| "#{base}_#{count}" }.find { |slug| taken.exclude?(slug) }
    end

    def pack_name(pack, integration)
      integration ? "#{integration.display_name}: #{pack}" : CHANGES_EVERYWHERE_NAME
    end

    def pack_description(pack, integration)
      case pack
      when PACK_READ then "Every tool on #{integration.display_name} that only reads."
      when PACK_CHANGES then "Every tool on #{integration.display_name} that changes something."
      when PACK_EVERYTHING then "Every tool on #{integration.display_name}, reads and changes."
      else "Every tool that changes something, on every connection."
      end
    end
  end

  def built_in? = pack.present?

  def read_pack? = pack == PACK_READ

  # What this set lets a member do without a grant, in words that follow "can" or "can no longer".
  def default_words = "read #{integration.display_name}'s tools"

  def edit_blocked_reason
    return unless built_in?

    kept_with = integration ? "#{integration.display_name}'s tools" : "every connection's tools"
    "#{name} is kept in step with #{kept_with}, so it cannot be changed by hand. Make your own set to pick abilities one by one."
  end

  def delete_blocked_reason
    return unless built_in?
    return "#{name} is built in, so it cannot be deleted. Revoke it from whoever holds it instead." unless integration

    "#{name} goes when #{integration.display_name} is disconnected, so it cannot be deleted by hand. Revoke it from whoever holds it instead."
  end

  def destroy_by_hand!
    blocked = delete_blocked_reason
    raise ActiveRecord::RecordInvalid.new(tap { errors.add(:base, blocked) }) if blocked

    destroy!
  end

  def keep_in_step
    @kept_in_step = true
    yield
  ensure
    @kept_in_step = false
  end

  def hold(action)
    return if role_actions.exists?(action_id: action.id)

    transaction(requires_new: true) { role_actions.create!(action_id: action.id) }
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def release(action)
    role_actions.where(action_id: action.id).destroy_all
  end

  def retire!
    keep_in_step { destroy! }
  end

  private

  def left_alone_by_hand
    return if @kept_in_step || !(built_in? || pack_changed?)
    return unless (changed & %w[name description slug pack integration_id]).any?

    errors.add(:base, edit_blocked_reason || "A set you made cannot become a built-in pack.")
  end

  def refuse_by_hand
    return if !built_in? || @kept_in_step || destroyed_by_association

    errors.add(:base, delete_blocked_reason)
    throw :abort
  end
end
