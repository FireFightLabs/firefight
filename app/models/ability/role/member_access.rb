# Who among the members can read or change through a connection's packs, as Who can do what chooses it: everyone, nobody
# or chosen people. Everyone is the pack's every_member flag, so a member who joins later has it too. A read pack held by
# every member is the default a member reads by (WorkspaceMembership#default_read?), and a changes pack held by every member
# reaches each of them as an unscoped grant would (Ability::Resolver). Chosen people are ordinary grants of the pack, the
# same rows the Permissions screen gives and revokes, so either place shows what the other did.
module Ability::Role::MemberAccess
  extend ActiveSupport::Concern

  EVERYONE = "everyone".freeze
  NOBODY = "nobody".freeze
  CHOSEN = "chosen".freeze
  CHOICES = [ EVERYONE, NOBODY, CHOSEN ].freeze
  # Beyond this many, a notice names the first few and counts the rest.
  NAMED_IN_NOTICE = 3

  # Where one pack stands for the members. people are those holding it by a grant when it is chosen people, and left_out
  # are members a No access or a lapsed grant keeps from a read every member otherwise has.
  Standing = Data.define(:role, :choice, :people_ids, :left_out_ids, :through)
  # Members not on a row who still reach its tools through other access, grouped by that access: a set or pack, or
  # abilities granted one by one (role nil).
  Through = Data.define(:role_id, :role_slug, :role_name, :people_ids)
  # One member's live grant as the resolver reads it, with each action it reaches. A grant of a set comes once per
  # action in the set.
  Reach = Data.define(:principal_id, :role_id, :role_slug, :role_name, :action_id, :no_access)
  # A connection's row: its read pack and its changes pack.
  Connection = Data.define(:integration, :read, :change)
  # Every connection's row, the members who can be chosen, and how many people the workspace has, admins included.
  Overview = Data.define(:connections, :members, :people_count)

  included do
    validate :every_member_only_on_connection_packs
  end

  class_methods do
    # Every connection's two rows, named as the Permissions screen names its packs, read from the grants as they stand now.
    def member_access_of(workspace)
      members = workspace.workspace_memberships.members.includes(:user).to_a.sort_by { |member| member.display_name.downcase }
      packs = workspace.ability_roles.where(pack: [ Ability::Role::PACK_READ, Ability::Role::PACK_CHANGES ])
                       .joins(:integration).merge(Integration.where(deleted_at: nil))
                       .includes(:integration, :grants, :role_actions)
      reach = reach_of(workspace, members)
      connections = packs.group_by(&:integration).filter_map do |integration, pair|
        by_pack = pair.index_by(&:pack)
        read, change = by_pack.values_at(Ability::Role::PACK_READ, Ability::Role::PACK_CHANGES)
        next unless read && change

        Connection.new(integration: integration, read: read.standing(members, reach), change: change.standing(members, reach))
      end
      Overview.new(connections: connections.sort_by { |connection| connection.integration.display_name.downcase },
                   members: members, people_count: workspace.workspace_memberships.count)
    end

    # Every live grant the members hold, each set opened into the actions it holds, read in one query the way
    # Ability::Resolver.compute reads one member's.
    def reach_of(workspace, members)
      Ability::Grant.live.where(workspace_id: workspace.id, principal_type: WorkspaceMembership.polymorphic_name, principal_id: members.map(&:id))
                    .left_joins(role: :role_actions)
                    .pluck(:principal_id, :role_id, "ability_roles.slug", "ability_roles.name", Arel.sql("COALESCE(ability_role_actions.action_id, ability_grants.action_id)"), :scope)
                    .map do |principal_id, role_id, role_slug, role_name, action_id, scope|
                      Reach.new(principal_id: principal_id, role_id: role_id, role_slug: role_slug, role_name: role_name, action_id: action_id,
                                no_access: Ability::Scope.no_access?(scope))
                    end
    end

    # The packs every member of the workspace holds without a grant, of the kind given.
    def held_by_every_member(workspace_id, pack)
      where(workspace_id: workspace_id, pack: pack, every_member: true).where.not(integration_id: nil)
    end

    # Read packs every member does not read by default, so a member reads their tools only through a grant.
    def read_by_chosen_members(workspace_id)
      where(workspace_id: workspace_id, pack: Ability::Role::PACK_READ, every_member: false).where.not(integration_id: nil)
    end
  end

  def member_access_pack? = integration_id.present? && [ Ability::Role::PACK_READ, Ability::Role::PACK_CHANGES ].include?(pack)

  # Whether every member's resolved grants depend on this pack, rather than only its holders'.
  def reaches_every_member? = member_access_pack? && (read_pack? ? !every_member? : every_member?)

  # reach is every member's live grants, from reach_of.
  def standing(members, reach = [])
    member_ids = members.map(&:id).to_set
    held = grants.select { |grant| grant.principal_type == WorkspaceMembership.name && member_ids.include?(grant.principal_id) }
    lapsed, live = held.partition { |grant| grant.no_access? || grant.expired? }
    if every_member?
      return Standing.new(role: self, choice: EVERYONE, people_ids: [], left_out_ids: read_pack? ? lapsed.map(&:principal_id) : [], through: [])
    end

    people_ids = live.map(&:principal_id)
    Standing.new(role: self, choice: people_ids.any? ? CHOSEN : NOBODY, people_ids: people_ids, left_out_ids: [],
                 through: through(reach, people_ids))
  end

  # Why this pack cannot be set to the choice for these people, or nil.
  def member_access_blocked_reason(choice, people = [])
    return "Only a connection's read or changes pack is chosen for every member." unless member_access_pack?
    return "Choose Everyone, Nobody or the people who can #{member_verb} #{integration.display_name}." unless CHOICES.include?(choice)
    return empty_pack_reason if role_actions.empty?
    return unless choice == CHOSEN
    return "Pick at least one person, or choose Nobody." if people.empty?

    "Admins can always do everything, so pick members only." if people.any?(&:admin_access?)
  end

  # Why the dropdown is not offered at all, or nil.
  def member_access_unavailable_reason = (empty_pack_reason if member_access_pack? && role_actions.empty?)

  # Everyone holds it by the pack itself, and No access a member had on a read pack goes so they read again. Nobody and
  # chosen people take the pack off every member and leave it to grants, revoking the grants of anyone not chosen and
  # granting it in every environment to anyone chosen who does not already hold it live.
  def let_members!(choice, people: [], by: nil)
    blocked = member_access_blocked_reason(choice, people)
    raise ActiveRecord::RecordInvalid.new(tap { errors.add(:base, blocked) }) if blocked

    transaction do
      held = grants.where(principal_type: WorkspaceMembership.name, principal_id: workspace.workspace_memberships.members.select(:id)).to_a
      update!(every_member: choice == EVERYONE)
      case choice
      when EVERYONE
        held.select(&:no_access?).each(&:destroy!)
        settle_waiting_requests(by) if pack == Ability::Role::PACK_CHANGES
      when NOBODY
        held.each(&:destroy!)
      when CHOSEN
        choose!(held, people, by)
      end
    end
  end

  def member_access_notice(choice, people = [])
    name = integration.display_name
    case choice
    when EVERYONE then "Members can #{member_verb} #{name}."
    when NOBODY then "Members can no longer #{member_verb} #{name}."
    else "#{people_words(people)} can #{member_verb} #{name}."
    end
  end

  private

  def member_verb = read_pack? ? "read" : "change"

  # Members the row leaves out who reach one of its tools anyway, through another set or a single ability. No access on a
  # pack outranks every set holding its tools, as it does in the resolver.
  def through(reach, chosen_ids)
    actions = role_actions.map(&:action_id).to_set
    withheld = reach.select { |row| row.no_access && row.role_id == id }.map(&:principal_id)
    others = reach.reject { |row| row.no_access || row.role_id == id || chosen_ids.include?(row.principal_id) || withheld.include?(row.principal_id) }
    others.select { |row| actions.include?(row.action_id) }.group_by { |row| [ row.role_id, row.role_slug, row.role_name ] }.map do |(role_id, role_slug, role_name), rows|
      Through.new(role_id: role_id, role_slug: role_slug, role_name: role_name, people_ids: rows.map(&:principal_id).uniq)
    end.sort_by { |access| [ access.role_id ? 0 : 1, access.role_name.to_s ] }
  end

  def empty_pack_reason
    read_pack? ? "#{integration.display_name} has no tools that only read." : "#{integration.display_name} has no tools that change anything."
  end

  def choose!(held, people, by)
    chosen = people.map(&:id)
    held.reject { |grant| chosen.include?(grant.principal_id) }.each(&:destroy!)
    holding = held.reject { |grant| grant.no_access? || grant.expired? }.map(&:principal_id)
    people.reject { |person| holding.include?(person.id) }.each do |person|
      Ability::Grant.grant!(workspace: workspace, principal: person, target: { role: self }, granted_by: by)
    end
  end

  # Members who asked for this pack hold it now, so their requests are answered as a grant of it would answer them.
  def settle_waiting_requests(by)
    requests = Ability::PackRequest.waiting.where(role_id: id)
    settled = requests.pluck(:id)
    requests.update_all(given_at: Time.current, given_by_id: (by.id if by.is_a?(WorkspaceMembership)), updated_at: Time.current)
    settled.each { |request_id| PackRequestSettledJob.perform_later(request_id) }
  end

  def people_words(people)
    names = people.map(&:display_name)
    return names.to_sentence(two_words_connector: " and ", last_word_connector: " and ") if names.size <= NAMED_IN_NOTICE

    others = names.size - (NAMED_IN_NOTICE - 1)
    "#{names.first(NAMED_IN_NOTICE - 1).join(', ')} and #{others} others"
  end

  def every_member_only_on_connection_packs
    errors.add(:every_member, "applies only to a connection's read or changes pack") if every_member? && !member_access_pack?
  end
end
