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
  READS_KEY_PREFIX = "reads:".freeze

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

      transaction { file_all(Ability::Action.where(source: integration.tools).to_a, packs_for!(integration)) }
    end

    # Puts one tool's action in the packs its read-only flag says, and takes it out of the others. Inside
    # filing_together the action waits and is filed with the rest when the block ends.
    def file!(action, integration)
      return if integration.deleted?

      waiting = waiting_to_file(integration)
      return waiting[action.id] = action if waiting

      transaction { file(action, packs_for!(integration)) }
    end

    # Files every action the block's tools minted in one pass when it ends, rather than one tool at a time. Discovery
    # saves each of a provider's tools in turn, and filing each one looked the packs up and wrote its pack rows on its own.
    def filing_together(integration)
      return yield if waiting_to_file(integration)

      filing = (ActiveSupport::IsolatedExecutionState[:ability_role_filing] ||= {})
      filing[integration.id] = {}
      begin
        result = yield
        waiting = filing.delete(integration.id)
      rescue StandardError
        file_waiting(filing.delete(integration.id), integration, failed: true)
        raise
      ensure
        filing.delete(integration.id)
      end
      file_waiting(waiting, integration)
      result
    end

    # What a grant of a connection's read pack holds beyond the tools in it: every read through a tool of that connection
    # that can also change things (Integrations::ReadGuards). The resolver lists it beside action keys, and no action
    # key has this shape.
    def reads_key(integration_id) = "#{READS_KEY_PREFIX}#{integration_id}"

    # The pack a member is told to ask for when a tool that changes something is refused, or nil.
    def to_ask_for(action)
      return unless action&.source.is_a?(Integration::Tool) && !action.read?

      find_by(integration_id: action.source.integration_id, pack: PACK_CHANGES)
    end

    private

    def file(action, packs)
      packs.each { |pack, role| wanted_packs(action).include?(pack) ? role.hold(action) : role.release(action) }
    end

    def wanted_packs(action)
      action.read? ? [ PACK_READ, PACK_EVERYTHING ] : [ PACK_CHANGES, PACK_EVERYTHING, PACK_CHANGES_EVERYWHERE ]
    end

    def waiting_to_file(integration)
      ActiveSupport::IsolatedExecutionState[:ability_role_filing]&.[](integration.id)
    end

    # A failed block still files what its tools minted before it failed, as filing them one at a time did. When the
    # failure aborted the surrounding transaction, that transaction takes those actions back with it, so there is
    # nothing left to file and the original error is the one raised.
    def file_waiting(waiting, integration, failed: false)
      return if waiting.empty? || integration.deleted?

      transaction { file_all(waiting.values, packs_for!(integration)) }
    rescue ActiveRecord::StatementInvalid
      raise unless failed
    end

    # Gives each action the rows file would, written in one pass: one read of what the packs hold, one insert of what is
    # missing and one delete of what no longer belongs. The unique index on a pack and an action keeps a row another
    # discovery wrote first, as hold does. Each pack that changed has its holders' caches cleared once it commits.
    def file_all(actions, packs)
      return if actions.empty?
      return actions.each { |action| file(action, packs) } if actions.any?(&:admin_only?)

      held = Ability::RoleAction.where(role_id: packs.values.map(&:id), action_id: actions.map(&:id))
                                .pluck(:id, :role_id, :action_id).to_h { |id, role_id, action_id| [ [ role_id, action_id ], id ] }
      missing = []
      leaving = []
      actions.each do |action|
        packs.each do |pack, role|
          row = held[[ role.id, action.id ]]
          if wanted_packs(action).include?(pack)
            missing << { role_id: role.id, action_id: action.id } unless row
          elsif row
            leaving << [ row, role.id ]
          end
        end
      end

      joined = missing.empty? ? [] : Ability::RoleAction.insert_all(missing, unique_by: %i[role_id action_id], returning: %i[role_id]).rows.flatten
      Ability::RoleAction.where(id: leaving.map(&:first)).delete_all if leaving.any?
      changed = packs.values.select { |role| (joined + leaving.map(&:last)).include?(role.id) }
      Ability::RoleAction.current_transaction.after_commit { changed.each { |role| Ability::Resolver.bust_for_role!(role) } } if changed.any?
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
